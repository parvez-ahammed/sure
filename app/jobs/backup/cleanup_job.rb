class Backup::CleanupJob < ApplicationJob
  queue_as :scheduled
  sidekiq_options lock: :until_executed, on_conflict: :reject

  # Filename pattern: sure_backup_YYYYMMDD_HHMMSS_vN.sbk
  TIMESTAMP_RE = /sure_backup_(\d{8})_(\d{6})_v\d+\.sbk\z/

  def perform
    config = Backup::Config.instance
    return unless config.enabled?

    cutoff = config.retention_days.days.ago.utc
    provider = Backup::Provider::Factory.for(config.provider_type)

    deleted = 0
    provider.list(prefix: "sure_backup_").each do |file|
      ts = parse_timestamp(file.filename)
      next unless ts # ignore files we cannot date safely
      next if ts >= cutoff

      provider.delete(file.remote_id)
      deleted += 1
    end

    Rails.logger.info("[Backup::CleanupJob] deleted=#{deleted} cutoff=#{cutoff.iso8601}")
    deleted
  end

  def parse_timestamp(filename)
    m = filename.match(TIMESTAMP_RE) or return nil
    Time.utc(
      m[1][0, 4].to_i, m[1][4, 2].to_i, m[1][6, 2].to_i,
      m[2][0, 2].to_i, m[2][2, 2].to_i, m[2][4, 2].to_i
    )
  rescue ArgumentError
    nil
  end
end
