class AddEnqueuedAtToWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :webhook_events, :enqueued_at, :datetime
    add_index :webhook_events, [ :status, :enqueued_at ]
  end
end
