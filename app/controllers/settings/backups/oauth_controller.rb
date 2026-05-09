class Settings::Backups::OauthController < ApplicationController
  layout "settings"

  guard_feature unless: -> { Backup.enabled? }

  def start
    unless Backup::OauthClient.configured?
      redirect_to settings_backups_path, alert: t(".not_configured") and return
    end

    state = SecureRandom.urlsafe_base64(32)
    session[:backup_oauth_state] = state

    redirect_to Backup::OauthClient.authorize_url(redirect_uri: callback_url, state: state),
                allow_other_host: true
  end

  def callback
    expected = session.delete(:backup_oauth_state)

    if params[:state].blank? || params[:state] != expected
      redirect_to settings_backups_path, alert: t(".state_mismatch") and return
    end

    if params[:error].present?
      redirect_to settings_backups_path, alert: t(".denied") and return
    end

    tokens = Backup::OauthClient.exchange_code(code: params[:code], redirect_uri: callback_url)
    cred   = Backup::Credential.find_or_initialize_by(provider_type: "google_drive")
    cred.save!(validate: false) if cred.new_record?

    cred.update_tokens!(
      access_token: tokens[:access_token],
      refresh_token: tokens[:refresh_token],
      expires_at: tokens[:expires_at],
      scope: tokens[:scope]
    )

    email = Backup::Provider::GoogleDrive.new(cred).fetch_account_email
    cred.update!(google_account_email: email) if email.present?

    redirect_to settings_backups_path, notice: t(".connected", email: email || "Google Drive")
  rescue Backup::OauthClient::ExchangeError => e
    redirect_to settings_backups_path, alert: t(".exchange_failed", message: e.message)
  end

  def disconnect
    cred = Backup::Credential.find_by(provider_type: "google_drive")
    if cred.present?
      Backup::GoogleRevoker.revoke(cred.refresh_token)
      cred.clear_tokens!
    end
    redirect_to settings_backups_path, notice: t(".disconnected")
  end

  private

    def callback_url
      oauth_callback_settings_backups_url
    end
end
