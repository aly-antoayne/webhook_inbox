require "openssl"

# Portfolio protocol: HMAC-SHA256(secret, "timestamp.raw_body").
# A real provider needs an adapter for its own signing contract.
class WebhookSignature
  TOLERANCE = 300

  def self.valid?(body:, timestamp:, signature:, secret:, now: Time.current.to_i)
    return false if secret.to_s.bytesize < 32
    return false unless timestamp.to_s.match?(/\A[0-9]{10}\z/)
    return false unless signature.to_s.match?(/\Asha256=[0-9a-f]{64}\z/)
    return false if (now - timestamp.to_i).abs > TOLERANCE

    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{body}")}"
    ActiveSupport::SecurityUtils.secure_compare(expected, signature)
  end
end
