require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  setup do
    @original_dashboard_env = ENV.to_h.slice("DASHBOARD_USERNAME", "DASHBOARD_PASSWORD")
    ENV["DASHBOARD_USERNAME"] = "test-operator"
    ENV["DASHBOARD_PASSWORD"] = "test-only-password"
    @auth_headers = { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("test-operator", "test-only-password") }
  end

  teardown do
    ENV.delete("DASHBOARD_USERNAME")
    ENV.delete("DASHBOARD_PASSWORD")
    ENV.update(@original_dashboard_env)
  end

  test "renders metrics and explicitly identifies the non-persistent queue" do
    get "/", headers: @auth_headers
    assert_response :success
    assert_select "h1", "Visão geral"
    assert_select "#workers", text: /não expõe processos/
  end

  test "filters events and escapes payload HTML" do
    event = WebhookEvent.create!(external_id: "unique-dashboard", event_type: "order.created", status: "failed", payload: { value: "<script>alert(1)</script>" })
    get dashboard_events_path, params: { q: "unique-dashboard", status: "failed" }, headers: @auth_headers
    assert_response :success
    assert_select "#events tbody tr", count: 1
    get dashboard_event_path(event), headers: @auth_headers
    assert_response :success
    assert_select "script:not([src])", count: 0
    assert_includes response.body, "&lt;script&gt;"
  end

  test "missing event returns not found" do
    get "/dashboard/events/0", headers: @auth_headers
    assert_response :not_found
  end

  test "event list paginates filtered data and preserves search parameters" do
    12.times { |i| WebhookEvent.create!(external_id: "pagination-#{i}", event_type: "order.created", status: "pending", payload: {}) }
    get dashboard_events_path, params: { q: "pagination-", event_type: "order.created" }, headers: @auth_headers
    assert_response :success
    assert_select "#events tbody tr", count: 10
    assert_select ".pagination a[href*='page=2'][href*='pagination-']", minimum: 1
    get dashboard_events_path, params: { q: "pagination-", page: 2 }, headers: @auth_headers
    assert_select "#events tbody tr", count: 2
    get dashboard_events_path, params: { q: "nonexistent-filter" }, headers: @auth_headers
    assert_select ".empty-state h3", "Nenhum evento encontrado"
  end

  test "documentation describes the real queue and authenticated protocol" do
    get dashboard_documentation_path, headers: @auth_headers
    assert_response :success
    assert_select "h1", "Documentação do Webhook Inbox"
    assert_includes response.body, "X-Webhook-Timestamp"
    assert_includes response.body, "Solid Queue"
    assert_not_includes response.body, "Sidekiq"
  end

  test "operator can enqueue a fictional scenario" do
    assert_difference("WebhookEvent.count", 2) do
      assert_enqueued_jobs 2, only: ProcessWebhookEventJob do
        post dashboard_demo_path, params: { scenario: "payment" }, headers: @auth_headers
      end
    end
    assert_response :see_other
    post dashboard_demo_path, params: { scenario: "unknown" }, headers: @auth_headers
    assert_response :unprocessable_entity
  end

  test "manual replay enqueues a failed event once and never replays a completed event" do
    event = webhook_events(:one)
    event.update!(status: "failed")
    assert_enqueued_with(job: ProcessWebhookEventJob, args: [ event.id ]) do
      post retry_dashboard_event_path(event), headers: @auth_headers
    end
    assert_response :see_other
    assert_equal "pending", event.reload.status
    assert_no_enqueued_jobs { post retry_dashboard_event_path(event), headers: @auth_headers }
    event.update!(status: "processed")
    assert_no_enqueued_jobs { post retry_dashboard_event_path(event), headers: @auth_headers }
    assert_equal "processed", event.reload.status
  end

  test "dashboard mutations require authentication and CSRF token" do
    assert_no_difference("WebhookEvent.count") { post dashboard_demo_path, params: { scenario: "payment" } }
    assert_response :unauthorized
    original = DashboardController.allow_forgery_protection
    DashboardController.allow_forgery_protection = true
    get "/dashboard", headers: @auth_headers
    csrf = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')["content"]
    assert_no_difference("WebhookEvent.count") { post dashboard_demo_path, params: { scenario: "payment" }, headers: @auth_headers }
    assert_response :unprocessable_entity
    assert_difference("WebhookEvent.count", 2) do
      post dashboard_demo_path, params: { scenario: "payment" }, headers: @auth_headers.merge("X-CSRF-Token" => csrf)
    end
    assert_response :see_other
  ensure
    DashboardController.allow_forgery_protection = original
  end

  test "dashboard fails closed without credentials in every environment" do
    original = ENV.to_h.slice("DASHBOARD_USERNAME", "DASHBOARD_PASSWORD")
    ENV.delete("DASHBOARD_USERNAME")
    ENV.delete("DASHBOARD_PASSWORD")
    get "/dashboard"
    assert_response :service_unavailable
  ensure
    ENV.delete("DASHBOARD_USERNAME")
    ENV.delete("DASHBOARD_PASSWORD")
    ENV.update(original)
  end

  test "configured authentication protects the dashboard and payload details" do
    original = ENV.to_h.slice("DASHBOARD_USERNAME", "DASHBOARD_PASSWORD")
    ENV["DASHBOARD_USERNAME"] = "test-operator"
    ENV["DASHBOARD_PASSWORD"] = "test-only-password"
    get "/dashboard"
    assert_response :unauthorized
    get dashboard_event_path(webhook_events(:one))
    assert_response :unauthorized
    authorization = ActionController::HttpAuthentication::Basic.encode_credentials("test-operator", "test-only-password")
    get "/dashboard", headers: { "HTTP_AUTHORIZATION" => authorization }
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
  ensure
    ENV.delete("DASHBOARD_USERNAME")
    ENV.delete("DASHBOARD_PASSWORD")
    ENV.update(original)
  end
end
