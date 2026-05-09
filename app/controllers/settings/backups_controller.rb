class Settings::BackupsController < ApplicationController
  layout "settings"

  guard_feature unless: -> { Backup.enabled? }

  before_action :load_credential,  only: [ :show, :update_config ]
  before_action :load_config,      only: [ :show, :update_config, :run_now ]
  before_action :set_breadcrumbs,  only: [ :show, :update_config ]
  before_action :load_runs,        only: [ :show, :update_config ]

  def show
  end

  def update_config
    if @config.update(config_params)
      redirect_to settings_backups_path, notice: t(".saved")
    else
      flash.now[:alert] = @config.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    end
  end

  def run_now
    unless @config.enabled?
      redirect_to settings_backups_path, alert: t(".disabled") and return
    end
    Backup::RunJob.perform_later(trigger: "manual")
    redirect_to settings_backups_path, notice: t(".enqueued")
  end

  def rotate_key
    config = Backup::Config.instance
    new_version = config.key_version + 1
    if Backup::KeyRegistry.material_for(new_version).present?
      config.update!(key_version: new_version)
      redirect_to settings_backups_path, notice: t(".rotated", version: new_version)
    end
  rescue Backup::KeyRegistry::Missing => e
    redirect_to settings_backups_path, alert: t(".missing_key", message: e.message)
  end

  def verify
    run = Backup::Run.where.not(remote_file_id: nil).recent.first
    if run.nil?
      redirect_to settings_backups_path, alert: t(".no_run") and return
    end

    provider = Backup::Provider::Factory.for(run.provider_type || Backup::Config.instance.provider_type)
    files    = provider.list(prefix: run.filename)
    file     = files.find { |f| f.remote_id == run.remote_file_id } || files.first

    if file.nil?
      redirect_to settings_backups_path, alert: t(".missing") and return
    end

    redirect_to settings_backups_path, notice: t(".ok", filename: file.filename, size: file.size)
  rescue Backup::Provider::Base::Error => e
    redirect_to settings_backups_path, alert: t(".failed", message: e.message)
  end

  private

    def load_credential
      @credential = Backup::Credential.find_or_initialize_by(provider_type: "google_drive")
    end

    def load_config
      @config = Backup::Config.instance
    end

    def load_runs
      @runs = Backup::Run.recent.limit(25)
    end

    def set_breadcrumbs
      @breadcrumbs = [
        [ "Home", root_path ],
        [ t("settings.backups.show.breadcrumb"), nil ]
      ]
    end

    def config_params
      params.require(:backup_config).permit(:enabled, :provider_type, :frequency, :retention_days, :hour_utc).tap do |p|
        p[:enabled] = ActiveModel::Type::Boolean.new.cast(p[:enabled]) if p.key?(:enabled)
      end
    end
end
