require "google/apis/drive_v3"
require "googleauth"

class Backup::Provider::GoogleDrive < Backup::Provider::Base
  CHUNK_SIZE      = 8 * 1024 * 1024
  DEFAULT_MIME    = "application/octet-stream".freeze
  FOLDER_MIME     = "application/vnd.google-apps.folder".freeze
  DEFAULT_FOLDER  = "Sure Backups".freeze

  def upload(io, filename:, metadata: {})
    ensure_folder!

    metadata = metadata.transform_keys(&:to_s)
    file_metadata = Google::Apis::DriveV3::File.new(
      name: filename,
      parents: [ credential.folder_id ],
      app_properties: metadata,
      mime_type: metadata["mime_type"] || DEFAULT_MIME
    )

    created = service.create_file(
      file_metadata,
      upload_source: io,
      content_type: file_metadata.mime_type,
      fields: "id, name, createdTime, size",
      options: Google::Apis::RequestOptions.new.tap { |o| o.retries = 3 }
    )

    RemoteFile.new(
      remote_id: created.id,
      filename: created.name,
      created_at: parse_time(created.created_time),
      size: created.size&.to_i
    )
  rescue Google::Apis::Error => e
    raise UploadError, "Google Drive upload failed: #{e.message}"
  end

  def list(prefix: nil)
    query = [ "trashed = false" ]
    query << "'#{credential.folder_id}' in parents" if credential.folder_id.present?
    query << "name contains '#{escape(prefix)}'" if prefix.present?

    files = []
    page_token = nil
    loop do
      page = service.list_files(
        q: query.join(" and "),
        spaces: "drive",
        fields: "nextPageToken, files(id, name, createdTime, size)",
        page_token: page_token,
        page_size: 100
      )
      Array(page.files).each do |f|
        files << RemoteFile.new(
          remote_id: f.id,
          filename: f.name,
          created_at: parse_time(f.created_time),
          size: f.size&.to_i
        )
      end
      page_token = page.next_page_token
      break if page_token.blank?
    end
    files
  rescue Google::Apis::Error => e
    raise Error, "Google Drive list failed: #{e.message}"
  end

  def delete(remote_id)
    service.delete_file(remote_id)
    true
  rescue Google::Apis::Error => e
    raise Error, "Google Drive delete failed: #{e.message}"
  end

  def verify_credentials!
    service.get_about(fields: "user(emailAddress), storageQuota(limit, usage)")
    true
  rescue Google::Apis::ClientError, Google::Apis::AuthorizationError, Signet::AuthorizationError => e
    raise CredentialError, e.message
  end

  def fetch_account_email
    about = service.get_about(fields: "user(emailAddress)")
    about&.user&.email_address
  rescue Google::Apis::Error, Signet::AuthorizationError
    nil
  end

  private

    def ensure_folder!
      return if credential.folder_id.present?

      meta = Google::Apis::DriveV3::File.new(
        name: credential.folder_name.presence || DEFAULT_FOLDER,
        mime_type: FOLDER_MIME
      )
      created = service.create_file(meta, fields: "id, name")
      credential.update!(folder_id: created.id, folder_name: created.name)
    end

    def service
      @service ||= begin
        s = Google::Apis::DriveV3::DriveService.new
        s.client_options.application_name = "Sure Backup"
        s.client_options.open_timeout_sec = 30
        s.client_options.send_timeout_sec = 600
        s.authorization = Backup::OauthClient.user_credentials_for(credential)
        s.request_options.retries = 3
        s
      end
    end

    def escape(str)
      str.to_s.gsub("'", "\\\\'")
    end

    def parse_time(value)
      return value if value.is_a?(Time)
      return nil if value.blank?
      Time.parse(value.to_s)
    rescue ArgumentError
      nil
    end
end
