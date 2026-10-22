class DashboardDemo
  SCENARIOS = { "payment" => "Pagamento aprovado", "retry" => "Falha temporária e recuperação", "refund" => "Reembolso integral", "invalid" => "Falha de validação" }.freeze

  def self.call(scenario)
    raise ArgumentError unless SCENARIOS.key?(scenario)

    order_id = "demo-#{SecureRandom.hex(6)}"
    types = [ "order.created", "payment.approved" ]
    types << "payment.refunded" if scenario == "refund"
    events = types.map do |type|
      payload = { "id" => "evt_#{SecureRandom.hex(8)}", "type" => type,
                  "data" => { "order_id" => order_id, "amount_cents" => 15990, "currency" => "BRL" } }
      payload["simulate_failure"] = true if scenario == "retry" && type == "payment.approved"
      payload["data"]["amount_cents"] = -1 if scenario == "invalid"
      WebhookEvent.create!(external_id: payload["id"], event_type: type, payload: payload, status: "pending")
    end
    events.each { |event| WebhookDelivery.enqueue(event) }
    events.last
  end
end
