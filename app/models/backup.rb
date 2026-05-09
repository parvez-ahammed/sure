module Backup
  module_function

  # Feature gate. Self-hosted single-tenant only; super_admin only.
  def enabled?(user: Current.user)
    Rails.application.config.app_mode.self_hosted? && user&.super_admin?
  end
end
