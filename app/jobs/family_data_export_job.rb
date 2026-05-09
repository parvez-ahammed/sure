class FamilyDataExportJob < ApplicationJob
  queue_as :default

  def perform(family_export)
    family_export.update!(status: :processing)

    exporter = Family::DataExporter.new(family_export.family)
    zip_file = exporter.generate_export

    if family_export.to_local_download?
      attach_local(family_export, zip_file)
    else
      upload_remote(family_export, zip_file)
    end

    family_export.update!(status: :completed)
  rescue => e
    Rails.logger.error "Family export failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    family_export.update!(status: :failed)
  end

  private

    def attach_local(family_export, zip_file)
      family_export.export_file.attach(
        io: zip_file,
        filename: family_export.filename,
        content_type: "application/zip"
      )
    end

    def upload_remote(family_export, zip_file)
      provider_type = family_export.destination
      Backup::Credential.verified.find_by!(provider_type: provider_type)
      provider = Backup::Provider::Factory.for(provider_type)

      remote = provider.upload(
        zip_file,
        filename: family_export.filename,
        metadata: { mime_type: "application/zip", source: "family_export", family_export_id: family_export.id }
      )

      family_export.update!(
        remote_file_id: remote.remote_id,
        remote_provider_type: provider_type
      )
    end
end
