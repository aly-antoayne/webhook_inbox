namespace :demo do
  desc "Enqueue fictional order/payment examples (development only)"
  task orders: :environment do
    abort "Demonstração disponível apenas em desenvolvimento" unless Rails.env.development?
    batch = SecureRandom.hex(4)
    %w[pending paid refunded retry].each do |scenario|
      data = { order_id: "demo-#{batch}-#{scenario}", amount_cents: 15990, currency: "BRL" }
      types = [ "order.created" ]
      types << "payment.approved" unless scenario == "pending"
      types << "payment.refunded" if scenario == "refunded"
      types.each do |type|
        payload = { id: "#{data[:order_id]}-#{type}", type: type, data: data }
        payload[:simulate_failure] = true if scenario == "retry" && type == "payment.approved"
        event = WebhookEvent.create!(external_id: payload[:id], event_type: type, payload: payload, status: "pending")
        WebhookDelivery.enqueue(event)
      end
    end
    puts "Demonstração #{batch} enfileirada. Inicie o worker e abra http://localhost:3000/dashboard"
  end
end
