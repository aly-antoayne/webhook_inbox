class WebhookAttempt < ApplicationRecord
  belongs_to :webhook_event
  validates :status, inclusion: { in: %w[processed retrying failed] }

  def duration_ms
    ((finished_at - started_at) * 1000).round
  end
end
