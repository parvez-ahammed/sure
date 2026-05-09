class Backup::Provider::Factory
  REGISTRY = {
    "google_drive" => "Backup::Provider::GoogleDrive"
  }.freeze

  class UnknownProvider < StandardError; end

  def self.for(provider_type)
    klass_name = REGISTRY[provider_type.to_s] or raise UnknownProvider, provider_type.to_s
    credential = Backup::Credential.find_by!(provider_type: provider_type.to_s)
    klass_name.constantize.new(credential)
  end

  def self.available_provider_types
    REGISTRY.keys
  end
end
