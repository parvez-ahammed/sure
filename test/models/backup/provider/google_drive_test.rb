require "test_helper"

class Backup::Provider::GoogleDriveTest < ActiveSupport::TestCase
  setup do
    Rails.application.config.x.backup.google_client_id     = "client-id"
    Rails.application.config.x.backup.google_client_secret = "client-secret"

    @cred = Backup::Credential.create!(
      provider_type: "google_drive",
      access_token: "at",
      refresh_token: "rt",
      token_expires_at: 1.hour.from_now,
      scope: Backup::OauthClient::SCOPE,
      folder_name: "Sure Backups"
    )

    @provider = Backup::Provider::GoogleDrive.new(@cred)

    @drive_service = mock("drive_service")
    Google::Apis::DriveV3::DriveService.stubs(:new).returns(@drive_service)
    @drive_service.stubs(:client_options).returns(OpenStruct.new)
    @drive_service.stubs(:request_options).returns(OpenStruct.new)
    @drive_service.stubs(:authorization=).with(any_parameters)
  end

  teardown do
    Rails.application.config.x.backup.google_client_id     = nil
    Rails.application.config.x.backup.google_client_secret = nil
  end

  test "ensure_folder! creates Sure Backups folder when folder_id is blank" do
    created_folder = OpenStruct.new(id: "folder-1", name: "Sure Backups")
    @drive_service.expects(:create_file).with do |meta, _opts|
      meta.name == "Sure Backups" && meta.mime_type == "application/vnd.google-apps.folder"
    end.returns(created_folder)

    @provider.send(:ensure_folder!)

    assert_equal "folder-1", @cred.reload.folder_id
  end

  test "ensure_folder! is a no-op when folder_id already set" do
    @cred.update!(folder_id: "existing-folder")
    @drive_service.expects(:create_file).never
    @provider.send(:ensure_folder!)
  end

  test "upload sends file under app folder and returns RemoteFile" do
    @cred.update!(folder_id: "folder-1")
    io = StringIO.new("dummy")

    created = OpenStruct.new(id: "file-1", name: "snap.sbk", created_time: "2026-05-01T10:00:00Z", size: 5)
    @drive_service.expects(:create_file).with do |meta, opts|
      meta.parents == [ "folder-1" ] &&
        meta.name == "snap.sbk" &&
        opts[:upload_source] == io
    end.returns(created)

    result = @provider.upload(io, filename: "snap.sbk", metadata: { "sha256" => "abc" })

    assert_equal "file-1", result.remote_id
    assert_equal "snap.sbk", result.filename
  end

  test "verify_credentials! triggers Drive about call and marks success" do
    @drive_service.expects(:get_about).returns(OpenStruct.new(user: OpenStruct.new(email_address: "x@example.com")))
    assert_equal true, @provider.verify_credentials!
  end

  test "verify_credentials! raises CredentialError on Signet::AuthorizationError" do
    @drive_service.expects(:get_about).raises(Signet::AuthorizationError.new("revoked"))
    assert_raises(Backup::Provider::Base::CredentialError) do
      @provider.verify_credentials!
    end
  end
end
