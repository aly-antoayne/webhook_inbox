require "test_helper"

class WebhookSignatureTest < ActiveSupport::TestCase
  test "requires exact raw bytes and correctly formatted signature and timestamp" do
    secret = "a" * 32
    now = 1_800_000_000
    body = '{"id":"evt_1"}'
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{now}.#{body}")}"
    args = { body: body, timestamp: now.to_s, signature: signature, secret: secret, now: now }
    assert WebhookSignature.valid?(**args)
    assert_not WebhookSignature.valid?(**args.merge(body: body + " "))
    assert_not WebhookSignature.valid?(**args.merge(secret: "b" * 32))
    assert_not WebhookSignature.valid?(**args.merge(timestamp: "#{now}junk"))
    assert_not WebhookSignature.valid?(**args.merge(signature: signature.delete_prefix("sha256=")))
    assert_not WebhookSignature.valid?(**args.merge(signature: "sha256=123"))
    assert_not WebhookSignature.valid?(**args.merge(now: now + 301))
    assert_not WebhookSignature.valid?(**args.merge(now: now - 301))
    assert_not WebhookSignature.valid?(**args.merge(secret: ""))
  end
end
