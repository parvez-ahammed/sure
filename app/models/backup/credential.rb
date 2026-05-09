class Backup::Credential < ApplicationRecord
  self.table_name = "backup_credentials"

  include Encryptable

  encrypts :access_token, :refresh_token if encryption_ready?

  validates :provider_type, presence: true, uniqueness: true

  scope :verified, -> { where.not(verified_at: nil) }

  def verified?
    verified_at.present?
  end

  def connected?
    refresh_token.present?
  end

  def expired?
    token_expires_at.present? && token_expires_at <= Time.current
  end

  def update_tokens!(access_token:, expires_at:, refresh_token: nil, scope: nil, email: nil)
    with_lock do
      self.access_token      = access_token
      self.token_expires_at  = expires_at
      self.refresh_token     = refresh_token if refresh_token.present?
      self.scope             = scope if scope.present?
      self.google_account_email = email if email.present?
      self.verified_at       = Time.current
      save!
    end
  end

  def clear_tokens!
    update!(
      access_token: nil,
      refresh_token: nil,
      token_expires_at: nil,
      verified_at: nil
    )
  end
end
