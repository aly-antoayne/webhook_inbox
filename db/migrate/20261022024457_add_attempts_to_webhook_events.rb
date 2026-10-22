class AddAttemptsToWebhookEvents < ActiveRecord::Migration[8.1]
def change
  add_column :webhook_events, :attempts, :integer,
             default: 0, null: false
end
end


