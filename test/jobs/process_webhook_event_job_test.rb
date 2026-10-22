require "test_helper"

class ProcessWebhookEventJobTest < ActiveJob::TestCase
  test "processa um evento pendente" do
    event = WebhookEvent.create!(
      external_id: SecureRandom.uuid,
      event_type: "payment.approved",
      payload: {},
      status: "pending"
    )

    ProcessWebhookEventJob.perform_now(event.id)

    event.reload

    assert_equal "processed", event.status
    assert_equal 1, event.attempts
  end

  test "nao processa novamente um evento concluido" do
    event = WebhookEvent.create!(
      external_id: SecureRandom.uuid,
      event_type: "payment.approved",
      payload: {},
      status: "processed",
      attempts: 1
    )

    ProcessWebhookEventJob.perform_now(event.id)

    event.reload

    assert_equal "processed", event.status
    assert_equal 1, event.attempts
  end

  test "tenta novamente depois de uma falha temporaria" do
  event = WebhookEvent.create!(
    external_id: SecureRandom.uuid,
    event_type: "payment.approved",
    payload: { "simulate_failure" => true },
    status: "pending"
  )

  assert_enqueued_with(
    job: ProcessWebhookEventJob,
    args: [event.id]
  ) do
    ProcessWebhookEventJob.perform_now(event.id)
  end

  event.reload

  assert_equal "pending", event.status
  assert_equal 1, event.attempts

  perform_enqueued_jobs

  event.reload

  assert_equal "processed", event.status
  assert_equal 2, event.attempts
end
end