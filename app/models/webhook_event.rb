class WebhookEvent < ApplicationRecord
  has_many :webhook_attempts, dependent: :destroy
  validates :external_id, presence: true, uniqueness: true
  validates :event_type, presence: true
end
