class FamilyExport < ApplicationRecord
  belongs_to :family

  has_one_attached :export_file, dependent: :purge_later

  enum :status, {
    pending: "pending",
    processing: "processing",
    completed: "completed",
    failed: "failed"
  }, default: :pending, validate: true

  enum :destination, {
    local_download: "local_download",
    google_drive: "google_drive"
  }, default: :local_download, validate: true, prefix: :to

  scope :ordered, -> { order(created_at: :desc) }

  def filename
    "sure_export_#{created_at.strftime('%Y%m%d_%H%M%S')}.zip"
  end

  def downloadable?
    return false unless completed?
    to_local_download? ? export_file.attached? : remote_file_id.present?
  end

  def remote?
    !to_local_download?
  end
end
