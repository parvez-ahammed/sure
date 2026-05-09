require "test_helper"

class Settings::Backups::OauthControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.config.x.backup.google_client_id     = "client-id"
    Rails.application.config.x.backup.google_client_secret = "client-secret"
    @user = users(:sure_support_staff)
    sign_in @user
  end

  teardown do
    Rails.application.config.x.backup.google_client_id     = nil
    Rails.application.config.x.backup.google_client_secret = nil
  end

  test "start redirects to Google authorize URL with state in session" do
    with_self_hosting do
      get oauth_start_settings_backups_path
      assert_response :redirect
      assert_match %r{accounts\.google\.com/o/oauth2/v2/auth}, @response.location

      state = session[:backup_oauth_state]
      assert state.present?
      assert_includes @response.location, "state=#{CGI.escape(state)}"
    end
  end

  test "start redirects with error when env not configured" do
    Rails.application.config.x.backup.google_client_id = nil
    with_self_hosting do
      get oauth_start_settings_backups_path
      assert_redirected_to settings_backups_path
      assert_equal I18n.t("settings.backups.oauth.start.not_configured"), flash[:alert]
    end
  end

  test "start blocked when feature disabled (not self-hosted)" do
    get oauth_start_settings_backups_path
    assert_response :forbidden
  end

  test "callback rejects state mismatch" do
    with_self_hosting do
      get oauth_callback_settings_backups_path, params: { code: "abc", state: "wrong" }
      assert_redirected_to settings_backups_path
      assert_equal I18n.t("settings.backups.oauth.callback.state_mismatch"), flash[:alert]
    end
  end

  test "callback handles user denial gracefully" do
    with_self_hosting do
      get oauth_start_settings_backups_path
      state = session[:backup_oauth_state]

      get oauth_callback_settings_backups_path, params: { error: "access_denied", state: state }
      assert_redirected_to settings_backups_path
      assert_equal I18n.t("settings.backups.oauth.callback.denied"), flash[:alert]
    end
  end

  test "callback success path persists tokens and email" do
    with_self_hosting do
      get oauth_start_settings_backups_path
      state = session[:backup_oauth_state]

      Backup::OauthClient.expects(:exchange_code).with(
        code: "code-1",
        redirect_uri: oauth_callback_settings_backups_url
      ).returns(
        access_token: "at",
        refresh_token: "rt",
        scope: Backup::OauthClient::SCOPE,
        expires_at: 1.hour.from_now
      )

      Backup::Provider::GoogleDrive.any_instance.expects(:fetch_account_email).returns("admin@example.com")

      get oauth_callback_settings_backups_path, params: { code: "code-1", state: state }

      assert_redirected_to settings_backups_path
      cred = Backup::Credential.find_by!(provider_type: "google_drive")
      assert_equal "admin@example.com", cred.google_account_email
      assert cred.connected?
      assert cred.verified?
    end
  end

  test "callback rolls back on exchange failure" do
    with_self_hosting do
      get oauth_start_settings_backups_path
      state = session[:backup_oauth_state]

      Backup::OauthClient.expects(:exchange_code).raises(Backup::OauthClient::ExchangeError, "boom")

      get oauth_callback_settings_backups_path, params: { code: "x", state: state }
      assert_redirected_to settings_backups_path
      assert_match(/boom/, flash[:alert])
      assert_nil Backup::Credential.find_by(provider_type: "google_drive")&.refresh_token
    end
  end

  test "disconnect calls revoker and clears tokens" do
    with_self_hosting do
      cred = Backup::Credential.create!(
        provider_type: "google_drive",
        access_token: "at",
        refresh_token: "rt",
        token_expires_at: 1.hour.from_now,
        verified_at: Time.current
      )

      Backup::GoogleRevoker.expects(:revoke).with("rt")

      delete oauth_disconnect_settings_backups_path

      assert_redirected_to settings_backups_path
      cred.reload
      assert_nil cred.refresh_token
      assert_nil cred.access_token
      assert_nil cred.verified_at
    end
  end
end
