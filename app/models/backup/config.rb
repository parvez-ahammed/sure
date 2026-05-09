class Backup::Config < ApplicationRecord
  self.table_name = "backup_configs"

  FREQUENCIES = %w[daily weekly monthly].freeze

  validates :frequency, inclusion: { in: FREQUENCIES }
  validates :retention_days, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 3650 }
  validates :hour_utc, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 23, only_integer: true }
  validates :key_version, numericality: { greater_than_or_equal_to: 1, only_integer: true }

  after_save :sync_scheduler!

  def self.instance
    first_or_create!
  end

  def provider_type
    "google_drive"
  end

  def cron_expression
    case frequency
    when "daily"   then "0 #{hour_utc} * * *"
    when "weekly"  then "0 #{hour_utc} * * 0"
    when "monthly" then "0 #{hour_utc} 1 * *"
    end
  end

  private

    def sync_scheduler!
      defined?(BackupScheduler) && BackupScheduler.sync!
    rescue StandardError => e
      Rails.logger.error("[Backup::Config] scheduler sync failed: #{e.class}: #{e.message}")
    end
end
