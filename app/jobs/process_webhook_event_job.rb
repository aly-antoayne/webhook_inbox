class ProcessWebhookEventJob < ApplicationJob
  class TemporaryError < StandardError; end

  queue_as :default
  # WebhookDelivery marks delivery only after a real enqueue succeeds.
  self.enqueue_after_transaction_commit = false

  retry_on TemporaryError, wait: 5.seconds, attempts: 3 do |job, error|
    event = WebhookEvent.find(job.arguments.first)
    event.update!(status: "failed")

    Rails.logger.error(
      "Evento #{event.external_id} falhou: #{error.message}"
    )
  end

  def perform(event_id)
    event = WebhookEvent.find(event_id)

    temporary_failure = false
    event.with_lock do
      return if event.status == "processed"
      started_at = Time.current
      attempt_message = "Processamento concluído com sucesso."
      event.increment!(:attempts)
      event.update!(status: "processing")
      if event.payload["simulate_failure"] == true && event.attempts == 1
        event.update!(status: "pending")
        temporary_failure = true
        attempt_message = "Falha temporária simulada. Nova tentativa em 5 segundos."
      else
        begin
          OrderEventProcessor.call(event)
          event.update!(status: "processed")
        rescue OrderEventProcessor::InvalidPayload, ActiveRecord::RecordInvalid
          event.update!(status: "failed")
          attempt_message = "Payload de pedido inválido ou valor/moeda divergente. Confira os dados enviados."
        end
      end
      event.webhook_attempts.create!(number: event.attempts, status: temporary_failure ? "retrying" : event.status,
        started_at: started_at, finished_at: Time.current, message: attempt_message)
    end
    raise TemporaryError, "Falha temporária simulada" if temporary_failure
  end
end
