require "test_helper"

class Backup::SnapshotBuilderTest < ActiveSupport::TestCase
  test "calls pg_dump with custom format and writes encrypted output" do
    fake_pgdump_output = ("BIN\0PG_DUMP\0PAYLOAD" * 100).b
    out_io = StringIO.new(+"".b)

    builder = Backup::SnapshotBuilder.new(out_io: out_io, key_version: 1)

    # version check passes
    builder.stubs(:verify_pg_dump_version!)

    # mock dump_database! to return a tempfile preloaded with fake bytes
    fake_dump = Tempfile.new([ "fake", ".pgdump" ], binmode: true)
    fake_dump.write(fake_pgdump_output)
    fake_dump.rewind
    builder.stubs(:dump_database!).returns(fake_dump)

    meta = builder.call

    assert_kind_of Hash, meta
    assert_equal 16, meta[:salt].bytesize
    assert_equal 12, meta[:iv].bytesize
    assert_equal 16, meta[:tag].bytesize

    # Output starts with header
    assert_equal "SUREBAK", out_io.string[0, 7]

    # Round-trip: decrypt → gunzip → equals fake input
    out_io.rewind
    decrypted = StringIO.new(+"".b)
    Backup::Cipher.decrypt_stream(out_io, decrypted, key_version: 1)
    decrypted.rewind
    gunzipped = Zlib::GzipReader.new(decrypted).read
    assert_equal fake_pgdump_output, gunzipped
  end

  test "raises VersionMismatch when pg_dump major != server major" do
    out_io = StringIO.new(+"".b)
    builder = Backup::SnapshotBuilder.new(out_io: out_io, key_version: 1)

    Open3.expects(:capture3).with(Backup::SnapshotBuilder::PG_DUMP_BIN, "--version")
         .returns([ "pg_dump (PostgreSQL) 15.4\n", "", OpenStruct.new(success?: true) ])
    ActiveRecord::Base.connection.stubs(:postgresql_version).returns(160000)

    assert_raises(Backup::SnapshotBuilder::VersionMismatch) { builder.call }
  end
end
