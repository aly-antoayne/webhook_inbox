require "test_helper"

class OrderProcessingTest < ActiveJob::TestCase
  def deliver(type, order_id:, amount: 12000)
    event = WebhookEvent.create!(external_id: SecureRandom.uuid, event_type: type, status: "pending",
      payload: { data: { order_id: order_id, amount_cents: amount, currency: "BRL" } })
    ProcessWebhookEventJob.perform_now(event.id)
    event.reload
  end

  test "creates pays and refunds an order without regression on late or repeated events" do
    id = SecureRandom.uuid
    assert_equal "processed", deliver("order.created", order_id: id).status
    assert_equal "pending", Order.find_by!(external_id: id).status
    payment = deliver("payment.approved", order_id: id)
    assert_equal "paid", Order.find_by!(external_id: id).status
    ProcessWebhookEventJob.perform_now(payment.id)
    assert_equal 1, payment.reload.attempts
    deliver("payment.refunded", order_id: id)
    deliver("order.created", order_id: id)
    deliver("payment.approved", order_id: id)
    assert_equal "refunded", Order.find_by!(external_id: id).status
    assert_equal 1, Order.where(external_id: id).count
  end

  test "payment arriving before order creation is retained" do
    id = SecureRandom.uuid
    deliver("payment.approved", order_id: id)
    deliver("order.created", order_id: id)
    assert_equal "paid", Order.find_by!(external_id: id).status
  end

  test "invalid and conflicting amounts fail without changing the order" do
    id = SecureRandom.uuid
    assert_equal "failed", deliver("order.created", order_id: id, amount: -1).status
    assert_nil Order.find_by(external_id: id)
    deliver("order.created", order_id: id)
    assert_equal "failed", deliver("payment.approved", order_id: id, amount: 1).status
    assert_equal "pending", Order.find_by!(external_id: id).status
  end
end
