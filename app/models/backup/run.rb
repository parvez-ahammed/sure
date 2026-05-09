class Backup::Run < ApplicationRecord
  self.table_name = "backup_runs"

  STATUSES = %w[pending running success failed].freeze
  TRIGGERS = %w[scheduled manual].freeze

  enum :status, STATUSES.index_with(&:itself), validate: true
  enum :trigger, TRIGGERS.index_with(&:itself), validate: true, prefix: :triggered_by

  scope :recent, -> { order(created_at: :desc) }
end
