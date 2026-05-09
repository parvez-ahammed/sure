require "test_helper"

class Backup::CredentialTest < ActiveSupport::TestCase
  setup do
    @cred = Backup::Credential.create!(provider_type: "google_drive")
  end

  test "connected? is false without refresh_token" do
    assert_not @cred.connected?
  end

  test "connected? is true with refresh_token" do
    @cred.update!(refresh_token: "rt-1")
    assert @cred.connected?
  end

  test "expired? respects token_expires_at" do
    @cred.update!(token_expires_at: 1.minute.from_now)
    assert_not @cred.expired?
    @cred.update!(token_expires_at: 1.minute.ago)
    assert @cred.expired?
  end

  test "expired? false when token_expires_at nil" do
    assert_not @cred.expired?
  end

  test "update_tokens! sets verified_at and preserves prior refresh_token when none supplied" do
    @cred.update!(refresh_token: "rt-old", verified_at: nil)
    @cred.update_tokens!(
      access_token: "at-new",
      refresh_token: nil,
      expires_at: 1.hour.from_now,
      scope: "https://www.googleapis.com/auth/drive.file",
      email: "admin@example.com"
    )
    @cred.reload
    assert_equal "rt-old", @cred.refresh_token
    assert_equal "at-new", @cred.access_token
    assert_equal "admin@example.com", @cred.google_account_email
    assert_not_nil @cred.verified_at
  end

  test "update_tokens! overwrites refresh_token when supplied (rotation)" do
    @cred.update!(refresh_token: "rt-old")
    @cred.update_tokens!(
      access_token: "at-new",
      refresh_token: "rt-new",
      expires_at: 1.hour.from_now
    )
    assert_equal "rt-new", @cred.reload.refresh_token
  end

  test "clear_tokens! wipes auth fields and verified_at" do
    @cred.update!(access_token: "at", refresh_token: "rt", token_expires_at: 1.hour.from_now, verified_at: Time.current)
    @cred.clear_tokens!
    @cred.reload
    assert_nil @cred.access_token
    assert_nil @cred.refresh_token
    assert_nil @cred.token_expires_at
    assert_nil @cred.verified_at
  end

  test "uniqueness on provider_type" do
    dup = Backup::Credential.new(provider_type: "google_drive")
    assert_not dup.valid?
    assert_includes dup.errors[:provider_type], "has already been taken"
  end
end
