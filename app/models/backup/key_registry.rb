# Maps backup key_version → secret material used for KDF.
#
# Lookup order:
#   1. Rails.application.credentials.backup&.historical_keys&.dig(key_version)
#   2. ENV["BACKUP_KEY_V#{key_version}"]
#   3. Rails.application.secret_key_base (treated as v1 fallback)
#
# When a key_version cannot be resolved, raises Missing so the failure is loud.
class Backup::KeyRegistry
  class Missing < StandardError; end

  def self.material_for(key_version)
    version = key_version.to_i
    raise Missing, "key_version must be >= 1" if version < 1

    if (creds = Rails.application.credentials.backup) && creds.respond_to?(:historical_keys)
      key = creds.historical_keys.is_a?(Hash) ? (creds.historical_keys[version] || creds.historical_keys[version.to_s]) : nil
      return key if key.present?
    end

    env_key = ENV["BACKUP_KEY_V#{version}"]
    return env_key if env_key.present?

    return Rails.application.secret_key_base if version == 1

    raise Missing, "no key material registered for key_version=#{version}"
  end

  def self.fingerprint(key_version)
    Digest::SHA256.hexdigest(material_for(key_version))[0, 8]
  rescue Missing
    nil
  end
end
