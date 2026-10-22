class CreateWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_events do |t|
      t.string :external_id
      t.string :event_type
      t.json :payload
      t.string :status

      t.timestamps
    end
  end
end
