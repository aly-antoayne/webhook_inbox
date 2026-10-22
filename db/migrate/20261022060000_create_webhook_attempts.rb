class CreateWebhookAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_attempts do |t|
      t.references :webhook_event, null: false, foreign_key: true
      t.integer :number, null: false
      t.string :status, null: false
      t.datetime :started_at, null: false
      t.datetime :finished_at, null: false
      t.string :message
      t.timestamps
    end
    add_index :webhook_attempts, [ :webhook_event_id, :number ], unique: true
  end
end
