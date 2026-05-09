require "test_helper"

class FamilyDataExportJobTest < ActiveJob::TestCase
  setup do
    @family = families(:dylan_family)
    @export = @family.family_exports.create!
  end

  test "marks export as processing then completed" do
    assert_equal "pending", @export.status

    perform_enqueued_jobs do
      FamilyDataExportJob.perform_later(@export)
    end

    @export.reload
    assert_equal "completed", @export.status
    assert @export.export_file.attached?
  end

  test "marks export as failed on error" do
    # Mock the exporter to raise an error
    Family::DataExporter.any_instance.stubs(:generate_export).raises(StandardError, "Export failed")

    perform_enqueued_jobs do
      FamilyDataExportJob.perform_later(@export)
    end

    @export.reload
    assert_equal "failed", @export.status
  end

  test "uploads to provider when destination is google_drive" do
    Backup::Credential.create!(
      provider_type: "google_drive",
      access_token: "at",
      refresh_token: "rt",
      token_expires_at: 1.hour.from_now,
      verified_at: Time.current
    )

    drive_export = @family.family_exports.create!(destination: "google_drive")

    fake_provider = mock("provider")
    fake_provider.expects(:upload).with do |io, filename:, metadata:|
      io.respond_to?(:read) && filename == drive_export.filename && metadata[:source] == "family_export"
    end.returns(Backup::Provider::Base::RemoteFile.new(
      remote_id: "drive-file-1",
      filename: drive_export.filename,
      created_at: Time.current,
      size: 100
    ))
    Backup::Provider::Factory.expects(:for).with("google_drive").returns(fake_provider)

    perform_enqueued_jobs { FamilyDataExportJob.perform_later(drive_export) }

    drive_export.reload
    assert_equal "completed", drive_export.status
    assert_equal "drive-file-1", drive_export.remote_file_id
    assert_equal "google_drive", drive_export.remote_provider_type
    assert_not drive_export.export_file.attached?
  end

  test "fails when destination credential not verified" do
    drive_export = @family.family_exports.create!(destination: "google_drive")

    perform_enqueued_jobs { FamilyDataExportJob.perform_later(drive_export) }

    drive_export.reload
    assert_equal "failed", drive_export.status
  end
end
