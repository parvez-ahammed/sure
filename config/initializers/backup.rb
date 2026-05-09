Rails.application.config.x.backup = ActiveSupport::OrderedOptions.new
Rails.application.config.x.backup.google_client_id     = ENV["BACKUP_GOOGLE_OAUTH_CLIENT_ID"]
Rails.application.config.x.backup.google_client_secret = ENV["BACKUP_GOOGLE_OAUTH_CLIENT_SECRET"]
