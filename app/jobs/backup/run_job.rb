require "tempfile"

class Backup::RunJob < ApplicationJob
  queue_as :scheduled

  sidekiq_options lock: :until_executed, on_conflict: :reject, retry: 3
  discard_on Backup::Cipher::IntegrityError
  discard_on Backup::SnapshotBuilder::VersionMismatch

  def perform(trigger: "scheduled")
    config = Backup::Config.instance
    return unless config.enabled?

    run = Backup::Run.create!(
      status: :running,
      started_at: Time.current,
      trigger: trigger,
      key_version: config.key_version,
      provider_type: config.provider_type
    )

    provider = Backup::Provider::Factory.for(config.provider_type)
    filename = "sure_backup_#{Time.current.utc.strftime('%Y%m%d_%H%M%S')}_v#{config.key_version}.sbk"

    Tempfile.create([ "sure_backup", ".sbk" ], binmode: true) do |tmp|
      meta = Backup::SnapshotBuilder.new(out_io: tmp, key_version: config.key_version).call
      tmp.flush
      tmp.rewind

      remote = provider.upload(
        tmp,
        filename: filename,
        metadata: {
          "sha256" => meta[:plaintext_sha256],
          "key_version" => config.key_version.to_s,
          "mime_type" => "application/octet-stream"
        }
      )

      run.update!(
        status: :success,
        completed_at: Time.current,
        filename: filename,
        remote_file_id: remote.remote_id,
        byte_size: tmp.size,
        plaintext_sha256: meta[:plaintext_sha256],
        salt: meta[:salt],
        duration_ms: ((Time.current - run.started_at) * 1000).to_i
      )
    end
  rescue => e
    Rails.logger.error("[Backup] #{e.class}: #{e.message}\n#{e.backtrace.first(20).join("\n")}")
    run&.update!(
      status: :failed,
      completed_at: Time.current,
      error_message: "#{e.class}: #{e.message}",
      duration_ms: run.started_at ? ((Time.current - run.started_at) * 1000).to_i : nil
    )
    raise
  end
end
