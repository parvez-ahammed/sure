class BackupScheduler
  JOB_NAME         = "backup_automated".freeze
  CLEANUP_JOB_NAME = "backup_cleanup".freeze
  CLEANUP_CRON     = "0 3 * * *".freeze # 03:00 UTC daily, 1h after default backup window

  def self.sync!
    config = Backup::Config.instance
    Rails.logger.info("[BackupScheduler] enabled=#{config.enabled?} freq=#{config.frequency} hour=#{config.hour_utc}")

    if config.enabled?
      upsert_job(config)
      upsert_cleanup_job
    else
      remove_job
      remove_cleanup_job
    end
  end

  def self.upsert_job(config)
    cron = config.cron_expression
    job = Sidekiq::Cron::Job.create(
      name: JOB_NAME,
      cron: cron,
      class: "Backup::RunJob",
      queue: "scheduled",
      args: [ { trigger: "scheduled" } ],
      description: "Encrypted database snapshot uploaded to configured backup provider"
    )

    if job.nil? || (job.respond_to?(:valid?) && !job.valid?)
      msg = job.respond_to?(:errors) ? job.errors.to_a.join(", ") : "unknown error"
      Rails.logger.error("[BackupScheduler] failed to create cron job: #{msg}")
      raise StandardError, "Failed to create backup schedule: #{msg}"
    end

    Rails.logger.info("[BackupScheduler] cron upserted: #{cron}")
    job
  end

  def self.upsert_cleanup_job
    Sidekiq::Cron::Job.create(
      name: CLEANUP_JOB_NAME,
      cron: CLEANUP_CRON,
      class: "Backup::CleanupJob",
      queue: "scheduled",
      description: "Removes backup files older than retention_days from the configured provider"
    )
  end

  def self.remove_job
    if (job = Sidekiq::Cron::Job.find(JOB_NAME))
      job.destroy
      Rails.logger.info("[BackupScheduler] cron removed")
    end
  end

  def self.remove_cleanup_job
    if (job = Sidekiq::Cron::Job.find(CLEANUP_JOB_NAME))
      job.destroy
    end
  end
end
