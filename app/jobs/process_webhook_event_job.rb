class ProcessWebhookEventJob < ApplicationJob
  class TemporaryError < StandardError; end

  queue_as :default

  retry_on TemporaryError, wait: 5.seconds, attempts: 3 do |job, error|
    event = WebhookEvent.find(job.arguments.first)
    event.update!(status: "failed")

    Rails.logger.error(
      "Evento #{event.external_id} falhou: #{error.message}"
    )
  end

  def perform(event_id)
    event = WebhookEvent.find(event_id)

    return if event.status == "processed"

    event.increment!(:attempts)
    event.update!(status: "processing")

    if event.payload["simulate_failure"] == true && event.attempts == 1
      event.update!(status: "pending")

      raise TemporaryError, "Falha temporária simulada"
    end

    Rails.logger.info(
      "Processando #{event.external_id}, tentativa #{event.attempts}"
    )

    event.update!(status: "processed")
  end
end