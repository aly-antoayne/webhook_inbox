require "test_helper"

class WebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
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

  test "recebe e salva um evento" do
    assert_difference("WebhookEvent.count", 1) do
      post "/webhooks", params: @payload, as: :json
    end

    assert_response :created

    event = WebhookEvent.find_by!(external_id: @payload[:id])

    assert_equal "payment.approved", event.event_type
    assert_equal 15000, event.payload.dig("data", "amount_cents")
  end

  test "nao duplica um evento recebido novamente" do
    post "/webhooks", params: @payload, as: :json

    assert_no_difference("WebhookEvent.count") do
      post "/webhooks", params: @payload, as: :json
    end

    assert_response :ok
    assert_equal "Evento já recebido", response.parsed_body["message"]
  end

  test "rejeita evento sem identificador" do
    @payload.delete(:id)

    assert_no_difference("WebhookEvent.count") do
      post "/webhooks", params: @payload, as: :json
    end

    assert_response :unprocessable_entity
  end
end