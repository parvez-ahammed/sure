require "open3"
require "tempfile"
require "zlib"

# Orchestrates: pg_dump (custom format) → gzip → AES-256-GCM encrypt → out_io.
#
# Strategy: pg_dump streams to a temp file (avoids pipe backpressure), then
# the builder gzips + encrypts that temp file into the caller-supplied out_io.
# This trades disk space (~2× gzipped DB size) for simplicity and bounded RSS.
class Backup::SnapshotBuilder
  PG_DUMP_BIN = ENV.fetch("PG_DUMP_BIN", "pg_dump").freeze

  class PgDumpError    < StandardError; end
  class VersionMismatch < StandardError; end

  def initialize(out_io:, key_version:)
    @out_io      = out_io
    @key_version = key_version
  end

  def call
    verify_pg_dump_version!

    raw   = dump_database!
    gzipd = gzip_to_tempfile(raw)

    cipher_meta = nil
    File.open(gzipd.path, "rb") do |f|
      cipher_meta = Backup::Cipher.encrypt_stream(f, @out_io, key_version: @key_version)
    end

    {
      plaintext_sha256: cipher_meta[:plaintext_sha256], # sha256 of gzipped pg_dump (ie. what gets fed to GCM)
      key_version: @key_version,
      salt: cipher_meta[:salt],
      iv: cipher_meta[:iv],
      tag: cipher_meta[:tag]
    }
  ensure
    raw&.close!
    gzipd&.close!
  end

  private

    def verify_pg_dump_version!
      out, err, status = Open3.capture3(PG_DUMP_BIN, "--version")
      raise PgDumpError, "pg_dump missing: #{err}" unless status.success?
      m = out.match(/pg_dump \(PostgreSQL\)\s+(\d+)/)
      raise PgDumpError, "cannot parse pg_dump --version output: #{out.inspect}" unless m
      dump_major = m[1].to_i
      db_major   = ActiveRecord::Base.connection.postgresql_version / 10_000
      return if dump_major == db_major
      raise VersionMismatch, "pg_dump major v#{dump_major} != server v#{db_major}"
    end

    def dump_database!
      cfg = ActiveRecord::Base.connection_db_config.configuration_hash
      env = {
        "PGHOST"     => cfg[:host].to_s,
        "PGPORT"     => cfg[:port].to_s,
        "PGUSER"     => cfg[:username].to_s,
        "PGPASSWORD" => cfg[:password].to_s,
        "PGDATABASE" => cfg[:database].to_s
      }.compact_blank

      tmp = Tempfile.new([ "sure_pgdump", ".pgdump" ], binmode: true)
      tmp.close

      args = [ PG_DUMP_BIN, "--format=custom", "--compress=0", "--no-owner", "--no-privileges", "--file=#{tmp.path}" ]
      out, err, status = Open3.capture3(env, *args)
      unless status.success?
        tmp.unlink
        raise PgDumpError, "pg_dump failed (exit #{status.exitstatus}): #{err.presence || out}"
      end
      tmp.open
      tmp
    end

    def gzip_to_tempfile(input_io)
      out = Tempfile.new([ "sure_pgdump", ".gz" ], binmode: true)
      gz  = Zlib::GzipWriter.new(out)
      input_io.binmode
      input_io.rewind
      while (chunk = input_io.read(64 * 1024))
        gz.write(chunk)
      end
      gz.close # closes underlying file too
      out.open
      out
    end
end
