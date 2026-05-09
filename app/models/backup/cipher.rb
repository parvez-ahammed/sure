require "openssl"
require "securerandom"
require "zlib"
require "digest"
require "stringio"

# Streaming AES-256-GCM cipher for backup files.
#
# File layout (decrypt-without-this-app friendly):
#
#   Offset  Len  Field
#   0       7    Magic "SUREBAK"
#   7       1    Version byte (0x01)
#   8       16   Salt
#   24      12   IV
#   36      N    Ciphertext (caller chooses what plaintext bytes are; convention is gzipped pg_dump)
#   end-16  16   GCM auth tag
#
# Key derivation: ActiveSupport::KeyGenerator(SECRET_KEY_BASE, iter=1000).generate_key(salt, 32)
class Backup::Cipher
  MAGIC      = "SUREBAK".b.freeze
  VERSION    = 0x01
  SALT_LEN   = 16
  IV_LEN     = 12
  TAG_LEN    = 16
  HEADER_LEN = MAGIC.bytesize + 1 + SALT_LEN + IV_LEN # 36
  CHUNK_SIZE = 64 * 1024
  KEY_BYTES  = 32

  class FormatError < StandardError; end
  class IntegrityError < StandardError; end

  # Encrypts the bytes from `input_io` to `output_io`.
  # Output_io receives header + ciphertext + tag in order.
  # Returns metadata: {salt:, iv:, tag:, plaintext_sha256:, key_version:}
  def self.encrypt_stream(input_io, output_io, key_version:)
    salt = SecureRandom.bytes(SALT_LEN)
    iv   = SecureRandom.bytes(IV_LEN)
    key  = derive_key(salt: salt, key_version: key_version)

    cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
    cipher.key = key
    cipher.iv  = iv

    header = MAGIC + VERSION.chr.b + salt + iv
    cipher.auth_data = header

    output_io.binmode
    output_io.write(header)

    sha256 = Digest::SHA256.new

    while (chunk = input_io.read(CHUNK_SIZE))
      next if chunk.empty?
      sha256.update(chunk)
      output_io.write(cipher.update(chunk))
    end
    output_io.write(cipher.final)
    output_io.write(cipher.auth_tag)

    {
      salt: salt,
      iv: iv,
      tag: cipher.auth_tag,
      plaintext_sha256: sha256.hexdigest,
      key_version: key_version
    }
  end

  # Decrypts an .sbk stream from input_io, writing plaintext bytes to output_io.
  # Returns metadata.
  def self.decrypt_stream(input_io, output_io, key_version: nil)
    input_io.binmode
    output_io.binmode

    header = input_io.read(HEADER_LEN)
    raise FormatError, "short header" if header.nil? || header.bytesize < HEADER_LEN
    raise FormatError, "bad magic"    unless header.byteslice(0, MAGIC.bytesize) == MAGIC

    version = header.getbyte(MAGIC.bytesize)
    raise FormatError, "unsupported version #{version}" unless version == VERSION

    salt = header.byteslice(MAGIC.bytesize + 1, SALT_LEN)
    iv   = header.byteslice(MAGIC.bytesize + 1 + SALT_LEN, IV_LEN)
    key  = derive_key(salt: salt, key_version: key_version || 1)

    rest = input_io.read
    raise FormatError, "short ciphertext" if rest.nil? || rest.bytesize < TAG_LEN
    tag        = rest.byteslice(rest.bytesize - TAG_LEN, TAG_LEN)
    ciphertext = rest.byteslice(0, rest.bytesize - TAG_LEN)

    cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
    cipher.key = key
    cipher.iv  = iv
    cipher.auth_tag  = tag
    cipher.auth_data = header

    output_io.write(cipher.update(ciphertext))
    output_io.write(cipher.final)

    { salt: salt, iv: iv, tag: tag, key_version: key_version || 1 }
  rescue OpenSSL::Cipher::CipherError => e
    raise IntegrityError, e.message
  end

  def self.derive_key(salt:, key_version:)
    secret = key_material(key_version)
    ActiveSupport::KeyGenerator.new(secret, iterations: 1_000).generate_key(salt, KEY_BYTES)
  end

  def self.key_material(key_version)
    Backup::KeyRegistry.material_for(key_version)
  end
end
