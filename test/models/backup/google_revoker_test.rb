require "test_helper"

class Backup::GoogleRevokerTest < ActiveSupport::TestCase
  ENDPOINT = "https://oauth2.googleapis.com/revoke".freeze

  test "revoke posts token to Google revoke endpoint" do
    stub = stub_request(:post, ENDPOINT)
             .with(body: hash_including("token" => "rt-1"))
             .to_return(status: 200, body: "")

    Backup::GoogleRevoker.revoke("rt-1")
    assert_requested(stub)
  end

  test "revoke is a no-op for blank token" do
    Backup::GoogleRevoker.revoke(nil)
    Backup::GoogleRevoker.revoke("")
    assert true
  end

  test "revoke swallows Faraday errors" do
    stub_request(:post, ENDPOINT).to_raise(Faraday::ConnectionFailed.new("nope"))

    assert_nothing_raised do
      Backup::GoogleRevoker.revoke("rt-1")
    end
  end

  test "revoke swallows non-2xx responses" do
    stub_request(:post, ENDPOINT).to_return(status: 400, body: '{"error":"invalid_token"}')

    assert_nothing_raised do
      Backup::GoogleRevoker.revoke("rt-1")
    end
  end
end
