require "test_helper"

class WebhookDeliveryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "successful delivery is marked and duplicate delivery does not enqueue again" do
    event = webhook_events(:one)
    assert_enqueued_with(job: ProcessWebhookEventJob, args: [ event.id ]) { WebhookDelivery.enqueue(event) }
    assert_not_nil event.reload.enqueued_at
    assert_no_enqueued_jobs { WebhookDelivery.enqueue(event) }
  end

  test "failed enqueue leaves a durable pending event for recovery" do
    event = webhook_events(:one)
    failing_job = Object.new
    failing_job.define_singleton_method(:perform_later) { |_| false }
    assert_raises(WebhookDelivery::Unavailable) { WebhookDelivery.enqueue(event, job_class: failing_job) }
    assert_nil event.reload.enqueued_at
    assert_equal "pending", event.status
    assert_enqueued_with(job: ProcessWebhookEventJob, args: [ event.id ]) { RecoverWebhookDeliveriesJob.perform_now }
    assert_not_nil event.reload.enqueued_at
    assert_no_enqueued_jobs { RecoverWebhookDeliveriesJob.perform_now }
  end
end
