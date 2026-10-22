class WebhookEvent < ApplicationRecord
  validates :external_id, presence: true, uniqueness: true
  validates :event_type, presence: true
end