class Backup::Provider::Base
  Error                = Class.new(StandardError)
  CredentialError      = Class.new(Error)
  UploadError          = Class.new(Error)
  RemoteFile           = Struct.new(:remote_id, :filename, :created_at, :size, keyword_init: true)

  def initialize(credential)
    @credential = credential
  end

  # @param io [IO] readable, rewound input stream
  # @param filename [String] remote filename to write
  # @param metadata [Hash] arbitrary key/value metadata to attach if supported
  # @return [RemoteFile]
  def upload(io, filename:, metadata: {})
    raise NotImplementedError
  end

  # @param prefix [String, nil]
  # @return [Array<RemoteFile>]
  def list(prefix: nil)
    raise NotImplementedError
  end

  # @param remote_id [String]
  def delete(remote_id)
    raise NotImplementedError
  end

  # @raise [CredentialError] if credentials are invalid or insufficient
  # @return [true]
  def verify_credentials!
    raise NotImplementedError
  end

  protected

    attr_reader :credential
end
