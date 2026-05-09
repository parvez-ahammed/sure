class Backup::GoogleRevoker
  ENDPOINT = "https://oauth2.googleapis.com/revoke".freeze

  def self.revoke(token)
    return if token.blank?
    Faraday.post(ENDPOINT) do |req|
      req.headers["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = URI.encode_www_form(token: token)
    end
  rescue Faraday::Error => e
    Rails.logger.warn("[Backup::GoogleRevoker] revoke failed: #{e.message}")
  end
end
