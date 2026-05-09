require "test_helper"

class Backup::CleanupJobTest < ActiveJob::TestCase
  setup do
    Backup::Config.instance.update!(enabled: true, retention_days: 30, provider_type: "google_drive")
  end

  test "no-op when config disabled" do
    Backup::Config.instance.update!(enabled: false)
    Backup::Provider::Factory.expects(:for).never
    Backup::CleanupJob.new.perform
  end

  test "deletes only files older than retention_days, by filename timestamp" do
    old_filename    = "sure_backup_20251001_020000_v1.sbk" # ~6 months old
    recent_filename = (Time.current.utc - 5.days).strftime("sure_backup_%Y%m%d_%H%M%S_v1.sbk")
    junk_filename   = "manual_export.zip" # no timestamp pattern → ignored

    files = [
      Backup::Provider::Base::RemoteFile.new(remote_id: "old",    filename: old_filename,    created_at: Time.current, size: 100),
      Backup::Provider::Base::RemoteFile.new(remote_id: "recent", filename: recent_filename, created_at: Time.current, size: 100),
      Backup::Provider::Base::RemoteFile.new(remote_id: "junk",   filename: junk_filename,   created_at: 10.years.ago, size: 100)
    ]

    fake_provider = mock
    fake_provider.expects(:list).with(prefix: "sure_backup_").returns(files)
    fake_provider.expects(:delete).with("old").once
    fake_provider.expects(:delete).with("recent").never
    fake_provider.expects(:delete).with("junk").never
    Backup::Provider::Factory.expects(:for).with("google_drive").returns(fake_provider)

    deleted = Backup::CleanupJob.new.perform
    assert_equal 1, deleted
  end
end
