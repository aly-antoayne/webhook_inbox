class DashboardMetrics
  attr_reader :counts, :total, :success_rate, :change, :series, :period, :since

  def initialize(period: "24h", now: Time.current)
    @period = period == "7d" ? "7d" : "24h"
    interval = @period == "7d" ? 1.day : 1.hour
    buckets = @period == "7d" ? 7 : 24
    start = @period == "7d" ? now.beginning_of_day : now.beginning_of_hour
    @since = start - (buckets - 1) * interval
    scope = WebhookEvent.where(created_at: @since..now)
    @counts = scope.group(:status).count
    @total = @counts.values.sum
    @success_rate = @total.zero? ? 0 : (100.0 * @counts.fetch("processed", 0) / @total).round(1)
    previous = WebhookEvent.where(created_at: (@since - buckets * interval)...@since).count
    @change = previous.zero? ? nil : (100.0 * (@total - previous) / previous).round(1)
    format = @period == "7d" ? "%Y-%m-%d" : "%Y-%m-%d %H"
    grouping = @period == "7d" ? Arel.sql("strftime('%Y-%m-%d', created_at)") : Arel.sql("strftime('%Y-%m-%d %H', created_at)")
    volumes = scope.group(grouping).count
    failures = scope.where(status: "failed").group(grouping).count
    @series = buckets.times.map do |index|
      time = @since + index * interval
      { time: time, count: volumes.fetch(time.utc.strftime(format), 0), failed: failures.fetch(time.utc.strftime(format), 0) }
    end
  end
end
