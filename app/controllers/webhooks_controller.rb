class WebhooksController < ApplicationController
  before_action :verify_signature, only: :create
  before_action :authenticate_reader, only: :index
  after_action { response.headers["Cache-Control"] = "no-store" }

  def create
    return render(json: { error: "Envie application/json" }, status: :unsupported_media_type) unless request.media_type == "application/json"

    payload = JSON.parse(request.raw_post)
    unless payload.is_a?(Hash) && %w[id type].all? { |key| payload[key].is_a?(String) && payload[key].present? && payload[key].length <= 255 }
      return render json: { errors: [ "id e type devem ser textos não vazios de até 255 caracteres" ] }, status: :unprocessable_entity
    end

    # Use only the signed body: query parameters cannot override the event.
    event = WebhookEvent.find_by(external_id: payload["id"])
    created = event.nil?
    if created
      event = WebhookEvent.create!(external_id: payload["id"], event_type: payload["type"], payload: payload, status: "pending")
    end
    if event.payload != payload
      return render json: { error: "Identificador já utilizado com outro payload" }, status: :conflict
    end

    WebhookDelivery.enqueue(event)
    if created
      render json: event, status: :created
    else
      render json: { message: "Evento já recebido", event: event }, status: :ok
    end
  rescue JSON::ParserError
    render json: { error: "JSON inválido" }, status: :bad_request
  rescue ActiveRecord::RecordInvalid => error
    render json: { errors: error.record.errors.full_messages }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    # A concurrent delivery won the insert; the sender can safely retry.
    response.headers["Retry-After"] = "1"
    render json: { error: "Recebimento concorrente; reenvie o mesmo evento" }, status: :conflict
  rescue WebhookDelivery::Unavailable
    response.headers["Retry-After"] = "5"
    render json: { error: "Evento salvo, mas a fila está indisponível. Reenvie o mesmo evento." }, status: :service_unavailable
  end

  def index
    render json: WebhookEvent.order(created_at: :desc, id: :desc).limit(100)
  end

  private
    def verify_signature
      secret = ENV["WEBHOOK_SIGNING_SECRET"]
      if secret.to_s.bytesize < 32
        return render json: { error: "Recebimento não configurado" }, status: :service_unavailable
      end

      valid = WebhookSignature.valid?(body: request.raw_post,
        timestamp: request.headers["X-Webhook-Timestamp"],
        signature: request.headers["X-Webhook-Signature"], secret: secret)
      render json: { error: "Assinatura inválida ou expirada" }, status: :unauthorized unless valid
    end

    def authenticate_reader
      expected = ENV["WEBHOOK_READ_TOKEN"]
      if expected.to_s.bytesize < 32
        return render json: { error: "Consulta não configurada" }, status: :service_unavailable
      end

      authorization = request.headers["Authorization"].to_s
      scheme, token = authorization.split(" ", 2)
      valid = scheme == "Bearer" && token.present? &&
        ActiveSupport::SecurityUtils.secure_compare(token, expected)
      unless valid
        response.headers["WWW-Authenticate"] = "Bearer"
        render json: { error: "Não autorizado" }, status: :unauthorized
      end
    end
end
