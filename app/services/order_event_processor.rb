# A local demonstration of a payment lifecycle; no external payment is executed.
class OrderEventProcessor
  class InvalidPayload < StandardError; end

  def self.call(event)
    return unless %w[order.created payment.approved payment.refunded].include?(event.event_type)

    data = event.payload["data"]
    # Preserve compatibility with generic webhooks that do not target an order.
    return if event.event_type != "order.created" && (!data.is_a?(Hash) || !data.key?("order_id"))
    unless data.is_a?(Hash) && data["order_id"].is_a?(String) && data["order_id"].present? &&
        data["amount_cents"].is_a?(Integer) && data["amount_cents"] >= 0 && %w[BRL USD EUR].include?(data["currency"])
      raise InvalidPayload, "Informe order_id, amount_cents inteiro e currency (BRL, USD ou EUR)"
    end

    order = Order.find_or_initialize_by(external_id: data["order_id"])
    order.lock! if order.persisted?
    if order.persisted? && (order.amount_cents != data["amount_cents"] || order.currency != data["currency"])
      raise InvalidPayload, "Valor ou moeda diverge do pedido"
    end
    order.amount_cents = data["amount_cents"]
    order.currency = data["currency"]
    # Monotonic transitions also handle duplicate and out-of-order delivery.
    order.status = "paid" if event.event_type == "payment.approved" && order.status != "refunded"
    order.status = "refunded" if event.event_type == "payment.refunded"
    order.save!
  end
end
