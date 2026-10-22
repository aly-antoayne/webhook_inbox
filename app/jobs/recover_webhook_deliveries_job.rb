class RecoverWebhookDeliveriesJob < ApplicationJob
  queue_as :default

  def perform
    WebhookEvent.where(status: "pending", enqueued_at: nil).order(:id).limit(100).each do |event|
      WebhookDelivery.enqueue(event)
    end
  end
end
