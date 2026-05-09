require "test_helper"

class BackupSchedulerTest < ActiveSupport::TestCase
  test "upserts cron job when enabled" do
    Backup::Config.instance.update!(enabled: true, frequency: "daily", hour_utc: 4)

    fake_job = OpenStruct.new(valid?: true)
    Sidekiq::Cron::Job.expects(:create).with(has_entries(
      name: BackupScheduler::JOB_NAME,
      cron: "0 4 * * *",
      class: "Backup::RunJob",
      queue: "scheduled"
    )).returns(fake_job)
    Sidekiq::Cron::Job.expects(:create).with(has_entries(
      name: BackupScheduler::CLEANUP_JOB_NAME,
      cron: BackupScheduler::CLEANUP_CRON,
      class: "Backup::CleanupJob",
      queue: "scheduled"
    )).returns(fake_job)

    BackupScheduler.sync!
  end

  test "removes cron job when disabled" do
    Backup::Config.instance.update!(enabled: false)
    primary_job = mock
    primary_job.expects(:destroy)
    cleanup_job = mock
    cleanup_job.expects(:destroy)
    Sidekiq::Cron::Job.expects(:find).with(BackupScheduler::JOB_NAME).returns(primary_job)
    Sidekiq::Cron::Job.expects(:find).with(BackupScheduler::CLEANUP_JOB_NAME).returns(cleanup_job)
    BackupScheduler.sync!
  end

  test "weekly cron expression" do
    Backup::Config.instance.update!(enabled: true, frequency: "weekly", hour_utc: 9)
    Sidekiq::Cron::Job.expects(:create).with(has_entry(cron: "0 9 * * 0")).returns(OpenStruct.new(valid?: true))
    Sidekiq::Cron::Job.stubs(:create).with(has_entries(name: BackupScheduler::CLEANUP_JOB_NAME)).returns(OpenStruct.new(valid?: true))
    BackupScheduler.sync!
  end

  test "monthly cron expression" do
    Backup::Config.instance.update!(enabled: true, frequency: "monthly", hour_utc: 0)
    Sidekiq::Cron::Job.expects(:create).with(has_entry(cron: "0 0 1 * *")).returns(OpenStruct.new(valid?: true))
    Sidekiq::Cron::Job.stubs(:create).with(has_entries(name: BackupScheduler::CLEANUP_JOB_NAME)).returns(OpenStruct.new(valid?: true))
    BackupScheduler.sync!
  end
end
