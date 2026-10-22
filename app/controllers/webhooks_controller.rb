class WebhooksController < ApplicationController
def create
  existing_event = WebhookEvent.find_by(external_id: params[:id])

  if existing_event
    render json: {
      message: "Evento já recebido",
      event: existing_event
    }, status: :ok
    return
  end

  event = WebhookEvent.create!(
    external_id: params[:id],
    event_type: params[:type],
    payload: request.request_parameters,
    status: "pending"
  )
  
  ProcessWebhookEventJob.perform_later(event.id)

  render json: event, status: :created
rescue ActiveRecord::RecordInvalid => error
  render json: {
    errors: error.record.errors.full_messages
  }, status: :unprocessable_entity
rescue ActiveRecord::RecordNotUnique
  render json: {
    message: "Evento já recebido"
  }, status: :ok
end

  def index
    events = WebhookEvent.order(created_at: :desc).limit(100)

    render json: events
  end
end