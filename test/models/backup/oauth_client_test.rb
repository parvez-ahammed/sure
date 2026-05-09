require "test_helper"

class Backup::OauthClientTest < ActiveSupport::TestCase
  REDIRECT = "https://example.test/settings/backups/oauth/callback".freeze

  setup do
    Rails.application.config.x.backup.google_client_id     = "client-id-123"
    Rails.application.config.x.backup.google_client_secret = "client-secret-456"
  end

  teardown do
    Rails.application.config.x.backup.google_client_id     = nil
    Rails.application.config.x.backup.google_client_secret = nil
  end

  test "configured? reflects env config" do
    assert Backup::OauthClient.configured?

    Rails.application.config.x.backup.google_client_id = nil
    assert_not Backup::OauthClient.configured?
  end

  test "authorize_url contains required params" do
    url = Backup::OauthClient.authorize_url(redirect_uri: REDIRECT, state: "state-token")
    uri = URI.parse(url)
    params = URI.decode_www_form(uri.query).to_h

    assert_equal "client-id-123", params["client_id"]
    assert_equal REDIRECT, params["redirect_uri"]
    assert_equal "state-token", params["state"]
    assert_equal "code", params["response_type"]
    assert_equal "offline", params["access_type"]
    assert_equal "consent", params["prompt"]
    assert_includes params["scope"], "drive.file"
  end

  test "exchange_code returns hash with tokens" do
    stub_request(:post, "https://oauth2.googleapis.com/token")
      .with(body: hash_including("code" => "abc", "grant_type" => "authorization_code"))
      .to_return(
        status: 200,
        body: JSON.dump(
          access_token: "at",
          refresh_token: "rt",
          expires_in: 3600,
          scope: "https://www.googleapis.com/auth/drive.file",
          token_type: "Bearer"
        ),
        headers: { "Content-Type" => "application/json" }
      )

    result = Backup::OauthClient.exchange_code(code: "abc", redirect_uri: REDIRECT)

    assert_equal "at", result[:access_token]
    assert_equal "rt", result[:refresh_token]
    assert_equal "https://www.googleapis.com/auth/drive.file", result[:scope]
    assert_in_delta (Time.current + 3600.seconds).to_f, result[:expires_at].to_f, 5
  end

  test "exchange_code raises on Google error response" do
    stub_request(:post, "https://oauth2.googleapis.com/token")
      .to_return(status: 400, body: JSON.dump(error: "invalid_grant"), headers: { "Content-Type" => "application/json" })

    assert_raises(Backup::OauthClient::ExchangeError) do
      Backup::OauthClient.exchange_code(code: "abc", redirect_uri: REDIRECT)
    end
  end

  test "raises MissingConfigError when env vars missing" do
    Rails.application.config.x.backup.google_client_id = nil

    assert_raises(Backup::OauthClient::MissingConfigError) do
      Backup::OauthClient.authorize_url(redirect_uri: REDIRECT, state: "s")
    end
  end

  test "user_credentials_for builds UserRefreshCredentials wired to token store" do
    cred = Backup::Credential.create!(
      provider_type: "google_drive",
      refresh_token: "rt",
      access_token: "at",
      token_expires_at: 1.hour.from_now,
      scope: "https://www.googleapis.com/auth/drive.file"
    )
    user_creds = Backup::OauthClient.user_credentials_for(cred)
    assert_kind_of Google::Auth::UserRefreshCredentials, user_creds
    assert_equal "client-id-123", user_creds.client_id
    assert_equal "rt", user_creds.refresh_token
  end
end
