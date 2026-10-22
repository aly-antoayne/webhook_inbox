require "test_helper"

class DashboardMetricsTest < ActiveSupport::TestCase
  test "hourly chart counts only events inside the selected window" do
    now = Time.utc(2030, 10, 22, 10, 30)
    create_event("first", "processed", now.beginning_of_hour - 23.hours)
    create_event("last", "failed", now - 5.minutes)
    create_event("outside", "pending", now - 3.days)
    create_event("future", "pending", now + 5.minutes)

    metrics = DashboardMetrics.new(now: now)
    assert_equal 2, metrics.total
    assert_equal 50.0, metrics.success_rate
    assert_equal 24, metrics.series.size
    assert_equal 1, metrics.series.first[:count]
    assert_equal 1, metrics.series.last[:failed]
    assert_equal metrics.total, metrics.series.sum { |point| point[:count] }
  end

  test "weekly chart fills empty days and compares the previous period" do
    now = Time.utc(2030, 10, 22, 10, 30)
    create_event("previous", "processed", now - 10.days)
    create_event("week-start", "processed", now.beginning_of_day - 6.days)
    create_event("today", "processed", now)

    metrics = DashboardMetrics.new(period: "7d", now: now)
    assert_equal 7, metrics.series.size
    assert_equal 2, metrics.total
    assert_equal 100.0, metrics.change
    assert_equal 100.0, metrics.success_rate
    assert_equal 0, metrics.series[1][:count]
  end

  test "unknown periods fall back to an empty hourly chart without division errors" do
    metrics = DashboardMetrics.new(period: "unknown", now: Time.utc(2040, 1, 1))
    assert_equal "24h", metrics.period
    assert_equal 0, metrics.total
    assert_equal 0, metrics.success_rate
    assert_nil metrics.change
    assert metrics.series.all? { |point| point[:count].zero? && point[:failed].zero? }
  end

  private
    def create_event(id, status, time)
      WebhookEvent.create!(external_id: "metrics-#{id}", event_type: "payment.approved", status: status, payload: {}, created_at: time)
    end
end
