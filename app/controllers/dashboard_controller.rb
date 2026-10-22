class DashboardController < ActionController::Base
  before_action :authenticate_dashboard
  before_action :load_navigation
  protect_from_forgery with: :exception
  after_action { response.headers["Cache-Control"] = "no-store" }
  layout "dashboard"

  def index
    @metrics = DashboardMetrics.new(period: params[:period])
    @events = filtered_events.limit(5)
    @orders = Order.order(updated_at: :desc).limit(10)
    @workers = WorkerSnapshot.call
  end

  def events
    scope = filtered_events
    @filtered_count = scope.count
    @pages = [ (@filtered_count / 10.0).ceil, 1 ].max
    @page = params[:page].to_i.clamp(1, @pages)
    @events = scope.offset((@page - 1) * 10).limit(10)
    @event_types = WebhookEvent.distinct.order(:event_type).pluck(:event_type)
    @metrics = DashboardMetrics.new
    @workers = WorkerSnapshot.call
  end

  def show
    @event = WebhookEvent.find(params[:id])
    @attempts = @event.webhook_attempts.order(:number)
    @recent_events = WebhookEvent.order(created_at: :desc).limit(8)
  end

  def documentation
  end

  def demo
    return head :forbidden if Rails.env.production?

    event = DashboardDemo.call(params[:scenario].to_s)
    redirect_to dashboard_event_path(event, notice: "demo"), status: :see_other
  rescue ArgumentError
    render plain: "Cenário de demonstração inválido", status: :unprocessable_entity
  rescue WebhookDelivery::Unavailable
    redirect_to dashboard_events_path(notice: "queue_unavailable"), status: :see_other
  end

  def retry_event
    event = WebhookEvent.find(params[:id])
    accepted = false
    event.with_lock do
      if event.status == "failed"
        event.update!(status: "pending", enqueued_at: nil)
        accepted = true
      end
    end
    WebhookDelivery.enqueue(event) if accepted
    redirect_to dashboard_event_path(event, notice: accepted ? "retry" : "retry_skipped"), status: :see_other
  rescue WebhookDelivery::Unavailable
    redirect_to dashboard_event_path(event, notice: "queue_unavailable"), status: :see_other
  end

  private
    def load_navigation
      @global_counts = WebhookEvent.group(:status).count
      @status = params[:status].to_s
      @query = params[:q].to_s.first(100)
      @event_type = params[:event_type].to_s.first(100)
      @section = action_name == "index" ? "overview" : (action_name == "documentation" ? "docs" : "events")
    end

    def filtered_events
      scope = WebhookEvent.order(created_at: :desc, id: :desc)
      scope = scope.where(status: @status) if %w[pending processing processed failed].include?(@status)
      scope = scope.where(event_type: @event_type) if @event_type.present?
      if @query.present?
        term = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
        scope = scope.where("external_id LIKE ? OR event_type LIKE ?", term, term)
      end
      scope
    end

    def authenticate_dashboard
      user = ENV["DASHBOARD_USERNAME"]
      password = ENV["DASHBOARD_PASSWORD"]
      if user.present? && password.present?
        authenticate_or_request_with_http_basic("Webhook Inbox") do |given_user, given_password|
          ActiveSupport::SecurityUtils.secure_compare(given_user, user) &
            ActiveSupport::SecurityUtils.secure_compare(given_password, password)
        end
      else
        render plain: "Configure DASHBOARD_USERNAME e DASHBOARD_PASSWORD para acessar o painel.", status: :service_unavailable
      end
    end
end
