require "googleauth"
require "googleauth/user_refresh"

class Backup::OauthClient
  AUTHORIZE_URL = "https://accounts.google.com/o/oauth2/v2/auth".freeze
  TOKEN_URL     = "https://oauth2.googleapis.com/token".freeze
  SCOPE         = "https://www.googleapis.com/auth/drive.file".freeze

  MissingConfigError = Class.new(StandardError)
  ExchangeError      = Class.new(StandardError)

  class << self
    def configured?
      client_id.present? && client_secret.present?
    end

    def authorize_url(redirect_uri:, state:)
      raise MissingConfigError, "BACKUP_GOOGLE_OAUTH_CLIENT_ID/SECRET not set" unless configured?

      params = {
        client_id: client_id,
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: SCOPE,
        access_type: "offline",
        prompt: "consent",
        include_granted_scopes: "false",
        state: state
      }
      "#{AUTHORIZE_URL}?#{URI.encode_www_form(params)}"
    end

    def exchange_code(code:, redirect_uri:)
      raise MissingConfigError, "BACKUP_GOOGLE_OAUTH_CLIENT_ID/SECRET not set" unless configured?

      response = Faraday.post(TOKEN_URL) do |req|
        req.headers["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = URI.encode_www_form(
          code: code,
          client_id: client_id,
          client_secret: client_secret,
          redirect_uri: redirect_uri,
          grant_type: "authorization_code"
        )
      end

      raise ExchangeError, "Google returned #{response.status}: #{response.body}" unless response.success?

      payload = JSON.parse(response.body)
      {
        access_token: payload["access_token"],
        refresh_token: payload["refresh_token"],
        scope: payload["scope"],
        expires_at: Time.current + payload["expires_in"].to_i.seconds
      }
    rescue Faraday::Error => e
      raise ExchangeError, "Token exchange transport error: #{e.message}"
    end

    def user_credentials_for(credential)
      raise MissingConfigError, "BACKUP_GOOGLE_OAUTH_CLIENT_ID/SECRET not set" unless configured?

      Google::Auth::UserRefreshCredentials.new(
        client_id: client_id,
        client_secret: client_secret,
        scope: SCOPE,
        refresh_token: credential.refresh_token,
        access_token: credential.access_token,
        expires_at: credential.token_expires_at
      )
    end

    private

      def client_id
        Rails.application.config.x.backup.google_client_id
      end

      def client_secret
        Rails.application.config.x.backup.google_client_secret
      end
  end
end
