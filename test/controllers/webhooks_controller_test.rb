require "test_helper"

class WebhooksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @original_security_env = ENV.to_h.slice("WEBHOOK_SIGNING_SECRET", "WEBHOOK_READ_TOKEN")
    ENV["WEBHOOK_SIGNING_SECRET"] = "signing-secret-for-tests-only-000000"
    ENV["WEBHOOK_READ_TOKEN"] = "read-token-for-tests-only-0000000000"
    @payload = {
      id: SecureRandom.uuid,
      type: "payment.approved",
      data: {
        payment_id: "pay_123",
        amount_cents: 15000,
        currency: "BRL"
      }
    }
  end

  teardown do
    ENV.delete("WEBHOOK_SIGNING_SECRET")
    ENV.delete("WEBHOOK_READ_TOKEN")
    ENV.update(@original_security_env)
  end

  def signed_post(payload = @payload, timestamp: Time.current.to_i, path: "/webhooks", body: nil)
    body ||= payload.to_json
    signature = OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("WEBHOOK_SIGNING_SECRET"), "#{timestamp}.#{body}")
    post path, params: body, headers: { "CONTENT_TYPE" => "application/json",
      "X-Webhook-Timestamp" => timestamp.to_s, "X-Webhook-Signature" => "sha256=#{signature}" }
  end

  test "recebe e salva um evento" do
    assert_difference("WebhookEvent.count", 1) do
      signed_post
    end

    assert_response :created

    event = WebhookEvent.find_by!(external_id: @payload[:id])

    assert_equal "payment.approved", event.event_type
    assert_equal 15000, event.payload.dig("data", "amount_cents")
  end

  test "nao duplica um evento recebido novamente" do
    signed_post

    assert_no_difference("WebhookEvent.count") do
      assert_no_enqueued_jobs { signed_post }
    end

    assert_response :ok
    assert_equal "Evento já recebido", response.parsed_body["message"]
  end

  test "rejeita evento sem identificador" do
    @payload.delete(:id)

    assert_no_difference("WebhookEvent.count") do
      signed_post
    end

    assert_response :unprocessable_entity
  end

  test "unsigned and stale deliveries cannot save or enqueue events" do
    assert_no_difference("WebhookEvent.count") do
      assert_no_enqueued_jobs do
        post "/webhooks", params: @payload, as: :json
        assert_response :unauthorized
        signed_post(timestamp: 6.minutes.ago.to_i)
        assert_response :unauthorized
        signed_post(timestamp: 6.minutes.from_now.to_i)
        assert_response :unauthorized
      end
    end
  end

  test "tampering with the signed body is rejected" do
    timestamp = Time.current.to_i.to_s
    signature = OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("WEBHOOK_SIGNING_SECRET"), "#{timestamp}.#{@payload.to_json}")
    @payload[:data][:amount_cents] = 1
    assert_no_difference("WebhookEvent.count") do
      post "/webhooks", params: @payload.to_json, headers: { "CONTENT_TYPE" => "application/json",
        "X-Webhook-Timestamp" => timestamp, "X-Webhook-Signature" => "sha256=#{signature}" }
      assert_response :unauthorized
    end
  end

  test "query parameters cannot override the signed body" do
    signed_post(path: "/webhooks?id=unsigned-id&type=order.created")
    assert_response :created
    assert_equal @payload[:id], response.parsed_body["external_id"]
    assert_equal "payment.approved", response.parsed_body["event_type"]
  end

  test "an identifier cannot be reused for a different signed payload" do
    signed_post
    @payload[:data][:amount_cents] = 1
    assert_no_enqueued_jobs { signed_post }
    assert_response :conflict
  end

  test "signed malformed bodies are rejected" do
    signed_post(body: "{")
    assert_response :bad_request
    signed_post(body: "[]")
    assert_response :unprocessable_entity
    signed_post(@payload.merge(id: 123))
    assert_response :unprocessable_entity
  end

  test "missing credentials disable receiving and reading" do
    ENV.delete("WEBHOOK_SIGNING_SECRET")
    ENV.delete("WEBHOOK_READ_TOKEN")
    post "/webhooks", params: @payload, as: :json
    assert_response :service_unavailable
    get "/webhooks"
    assert_response :service_unavailable
  end

  test "reading requires its own bearer token" do
    get "/webhooks"
    assert_response :unauthorized
    get "/webhooks", headers: { "Authorization" => "Bearer #{ENV.fetch('WEBHOOK_SIGNING_SECRET')}" }
    assert_response :unauthorized
    get "/webhooks", headers: { "Authorization" => "Bearer #{ENV.fetch('WEBHOOK_READ_TOKEN')}" }
    assert_response :success
    assert_kind_of Array, response.parsed_body
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "signed order and payment move an order from pending to paid" do
    order_id = SecureRandom.uuid
    data = { order_id: order_id, amount_cents: 15990, currency: "BRL" }
    perform_enqueued_jobs do
      signed_post({ id: SecureRandom.uuid, type: "order.created", data: data })
      assert_response :created
    end
    assert_equal "pending", Order.find_by!(external_id: order_id).status
    perform_enqueued_jobs do
      signed_post({ id: SecureRandom.uuid, type: "payment.approved", data: data })
      assert_response :created
    end
    order = Order.find_by!(external_id: order_id)
    assert_equal "paid", order.status
    assert_equal 15990, order.amount_cents
  end

  test "queue failure returns 503 and the same signed event recovers without duplication" do
    previous_adapter = ProcessWebhookEventJob.queue_adapter
    unavailable_adapter = Object.new
    unavailable_adapter.define_singleton_method(:enqueue) { |_| raise ActiveJob::EnqueueError, "Queue unavailable in test" }
    ProcessWebhookEventJob.enable_test_adapter(unavailable_adapter)
    signed_post
    assert_response :service_unavailable
    event = WebhookEvent.find_by!(external_id: @payload[:id])
    assert_nil event.enqueued_at
    assert_equal "pending", event.status

    ProcessWebhookEventJob.enable_test_adapter(previous_adapter)
    assert_no_difference("WebhookEvent.count") do
      assert_enqueued_with(job: ProcessWebhookEventJob, args: [ event.id ]) { signed_post }
    end
    assert_response :ok
    assert_not_nil event.reload.enqueued_at
  ensure
    ProcessWebhookEventJob.enable_test_adapter(previous_adapter)
  end
end
