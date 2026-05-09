require "test_helper"

class Backup::RunJobTest < ActiveJob::TestCase
  setup do
    Backup::Config.instance.update!(enabled: true, key_version: 1, provider_type: "google_drive")
  end

  test "no-op when config disabled" do
    Backup::Config.instance.update!(enabled: false)
    assert_no_difference -> { Backup::Run.count } do
      Backup::RunJob.new.perform(trigger: "manual")
    end
  end

  test "happy path creates Run, calls SnapshotBuilder + provider.upload, marks success" do
    fake_provider = mock
    fake_provider.expects(:upload).returns(
      Backup::Provider::Base::RemoteFile.new(remote_id: "rid-9", filename: "x", created_at: Time.current, size: 1234)
    )
    Backup::Provider::Factory.expects(:for).with("google_drive").returns(fake_provider)

    fake_meta = { plaintext_sha256: "deadbeef", key_version: 1, salt: "s" * 16, iv: "i" * 12, tag: "t" * 16 }
    Backup::SnapshotBuilder.any_instance.expects(:call).returns(fake_meta)

    assert_difference -> { Backup::Run.count }, 1 do
      Backup::RunJob.new.perform(trigger: "manual")
    end

    run = Backup::Run.recent.first
    assert run.success?
    assert_equal "manual", run.trigger
    assert_equal "rid-9", run.remote_file_id
    assert_equal "deadbeef", run.plaintext_sha256
  end

  test "marks Run failed on provider error and re-raises" do
    Backup::Provider::Factory.expects(:for).raises(Backup::Provider::Base::UploadError, "boom")

    assert_raises(Backup::Provider::Base::UploadError) do
      Backup::RunJob.new.perform(trigger: "scheduled")
    end
    run = Backup::Run.recent.first
    assert run.failed?
    assert_match(/boom/, run.error_message)
  end
end
