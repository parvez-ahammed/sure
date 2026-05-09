require "test_helper"

class Settings::BackupsControllerTest < ActionDispatch::IntegrationTest
  test "forbidden when not self hosted" do
    sign_in users(:sure_support_staff)
    get settings_backups_url
    assert_response :forbidden
  end

  test "forbidden for non super_admin even when self hosted" do
    sign_in users(:family_admin)
    with_self_hosting do
      get settings_backups_url
      assert_response :forbidden
    end
  end

  test "super_admin can view show page when oauth not configured" do
    sign_in users(:sure_support_staff)
    Rails.application.config.x.backup.google_client_id     = nil
    Rails.application.config.x.backup.google_client_secret = nil

    with_self_hosting do
      get settings_backups_url
      assert_response :success
      assert_match I18n.t("settings.backups.show.oauth_unconfigured_html").gsub(/<[^>]+>/, "")[0, 30],
                   @response.body
    end
  end

  test "super_admin sees Connect button when configured but not connected" do
    sign_in users(:sure_support_staff)
    Rails.application.config.x.backup.google_client_id     = "id"
    Rails.application.config.x.backup.google_client_secret = "secret"

    with_self_hosting do
      get settings_backups_url
      assert_response :success
      assert_match I18n.t("settings.backups.show.connect"), @response.body
    end
  ensure
    Rails.application.config.x.backup.google_client_id     = nil
    Rails.application.config.x.backup.google_client_secret = nil
  end

  test "super_admin sees Disconnect when credential connected" do
    sign_in users(:sure_support_staff)
    Rails.application.config.x.backup.google_client_id     = "id"
    Rails.application.config.x.backup.google_client_secret = "secret"

    Backup::Credential.create!(
      provider_type: "google_drive",
      access_token: "at",
      refresh_token: "rt",
      token_expires_at: 1.hour.from_now,
      verified_at: Time.current,
      google_account_email: "admin@example.com",
      folder_name: "Sure Backups"
    )

    with_self_hosting do
      get settings_backups_url
      assert_response :success
      assert_match I18n.t("settings.backups.show.disconnect"), @response.body
      assert_match "admin@example.com", @response.body
    end
  ensure
    Rails.application.config.x.backup.google_client_id     = nil
    Rails.application.config.x.backup.google_client_secret = nil
  end

  test "update_config saves schedule" do
    sign_in users(:sure_support_staff)
    with_self_hosting do
      patch update_config_settings_backups_url, params: {
        backup_config: { enabled: "1", frequency: "daily", retention_days: 30, hour_utc: 2 }
      }
      assert_redirected_to settings_backups_url
      cfg = Backup::Config.instance
      assert cfg.enabled?
      assert_equal "daily", cfg.frequency
    end
  end

  test "run_now requires enabled config" do
    sign_in users(:sure_support_staff)
    Backup::Config.instance.update!(enabled: false)
    with_self_hosting do
      post run_now_settings_backups_url
      assert_redirected_to settings_backups_url
      assert_equal I18n.t("settings.backups.run_now.disabled"), flash[:alert]
    end
  end

  test "run_now enqueues job when enabled" do
    sign_in users(:sure_support_staff)
    Backup::Config.instance.update!(enabled: true, frequency: "daily", retention_days: 30, hour_utc: 2)

    Backup::RunJob.expects(:perform_later).with(trigger: "manual")

    with_self_hosting do
      post run_now_settings_backups_url
      assert_redirected_to settings_backups_url
    end
  end
end
