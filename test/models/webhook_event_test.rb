require "test_helper"

class WebhookEventTest < ActiveSupport::TestCase
  setup do
    @event = WebhookEvent.new(
      external_id: SecureRandom.uuid,
      event_type: "payment.approved",
      payload: {
        "data" => {
          "payment_id" => "pay_123",
          "amount_cents" => 15000,
          "currency" => "BRL"
        }
      },
      status: "pending"
    )
  end

  test "aceita um evento com identificador e tipo" do
    assert @event.valid?, @event.errors.full_messages.join(", ")
  end

  test "rejeita um evento sem identificador" do
    @event.external_id = nil

    assert_not @event.valid?
    assert @event.errors.added?(:external_id, :blank)
  end

  test "rejeita um evento sem tipo" do
    @event.event_type = nil

    assert_not @event.valid?
    assert @event.errors.added?(:event_type, :blank)
  end

  test "rejeita um identificador que ja foi cadastrado" do
    @event.save!

    duplicate = @event.dup

    assert_not duplicate.valid?
    assert duplicate.errors.added?(
      :external_id,
      :taken,
      value: @event.external_id
    )
  end
end
