class WebhookDelivery
  class Unavailable < StandardError; end

  def self.enqueue(event, job_class: ProcessWebhookEventJob)
    event.with_lock do
      return if event.enqueued_at.present? || event.status != "pending"

      job = job_class.perform_later(event.id)
      raise Unavailable unless job
      event.update!(enqueued_at: Time.current)
    end
  rescue ActiveRecord::ActiveRecordError, SolidQueue::Job::EnqueueError
    # The event was committed before delivery, so it can be recovered later.
    raise Unavailable
  end
end
