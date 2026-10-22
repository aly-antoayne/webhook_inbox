class AddUniqueIndexToWebhookEventsExternalId < ActiveRecord::Migration[8.1]
def change
  add_index :webhook_events, :external_id, unique: true
end
end
