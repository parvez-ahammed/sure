require "test_helper"

class Backup::CipherTest < ActiveSupport::TestCase
  test "round-trip encrypt then decrypt yields original plaintext" do
    plaintext = "The quick brown fox jumps over the lazy dog. " * 200
    enc_io = StringIO.new(+"".b)

    meta = Backup::Cipher.encrypt_stream(StringIO.new(plaintext), enc_io, key_version: 1)
    assert_equal 16, meta[:salt].bytesize
    assert_equal 12, meta[:iv].bytesize
    assert_equal 16, meta[:tag].bytesize

    enc_io.rewind
    dec_io = StringIO.new(+"".b)
    Backup::Cipher.decrypt_stream(enc_io, dec_io, key_version: 1)
    assert_equal plaintext, dec_io.string
  end

  test "header has SUREBAK magic + version byte" do
    enc_io = StringIO.new(+"".b)
    Backup::Cipher.encrypt_stream(StringIO.new("hi"), enc_io, key_version: 1)
    enc_io.rewind
    header = enc_io.read(8)
    assert_equal "SUREBAK", header[0, 7]
    assert_equal 0x01, header.getbyte(7)
  end

  test "tampered ciphertext raises IntegrityError" do
    enc_io = StringIO.new(+"".b)
    Backup::Cipher.encrypt_stream(StringIO.new("payload payload payload"), enc_io, key_version: 1)
    bytes = enc_io.string.dup
    # flip a byte in the middle of ciphertext (after 36-byte header, before 16-byte tag)
    flip_at = Backup::Cipher::HEADER_LEN + 2
    bytes.setbyte(flip_at, bytes.getbyte(flip_at) ^ 0xFF)

    assert_raises(Backup::Cipher::IntegrityError) do
      Backup::Cipher.decrypt_stream(StringIO.new(bytes), StringIO.new(+"".b), key_version: 1)
    end
  end

  test "wrong key raises IntegrityError" do
    enc_io = StringIO.new(+"".b)
    Backup::Cipher.encrypt_stream(StringIO.new("payload"), enc_io, key_version: 1)

    Backup::Cipher.stub(:key_material, "different_secret_key_base") do
      assert_raises(Backup::Cipher::IntegrityError) do
        Backup::Cipher.decrypt_stream(StringIO.new(enc_io.string), StringIO.new(+"".b), key_version: 1)
      end
    end
  end

  test "bad magic raises FormatError" do
    bytes = ("WRONGMK" + 0x01.chr + ("\0" * (Backup::Cipher::HEADER_LEN - 8)) + ("\0" * 17)).b
    assert_raises(Backup::Cipher::FormatError) do
      Backup::Cipher.decrypt_stream(StringIO.new(bytes), StringIO.new(+"".b), key_version: 1)
    end
  end
end
