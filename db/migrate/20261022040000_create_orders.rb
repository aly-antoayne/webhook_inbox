class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.string :external_id, null: false
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "BRL"
      t.string :status, null: false, default: "pending"
      t.timestamps
    end
    add_index :orders, :external_id, unique: true
  end
end
