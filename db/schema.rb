# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_22_060000) do
  create_table "orders", force: :cascade do |t|
    t.string "external_id", null: false
    t.integer "amount_cents", null: false
    t.string "currency", default: "BRL", null: false
    t.string "status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_orders_on_external_id", unique: true
  end

  create_table "webhook_attempts", force: :cascade do |t|
    t.integer "webhook_event_id", null: false
    t.integer "number", null: false
    t.string "status", null: false
    t.datetime "started_at", null: false
    t.datetime "finished_at", null: false
    t.string "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["webhook_event_id", "number"], name: "index_webhook_attempts_on_webhook_event_id_and_number", unique: true
    t.index ["webhook_event_id"], name: "index_webhook_attempts_on_webhook_event_id"
  end

  create_table "webhook_events", force: :cascade do |t|
    t.string "external_id"
    t.string "event_type"
    t.json "payload"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "enqueued_at"
    t.index ["external_id"], name: "index_webhook_events_on_external_id", unique: true
    t.index ["status", "enqueued_at"], name: "index_webhook_events_on_status_and_enqueued_at"
  end

  add_foreign_key "webhook_attempts", "webhook_events"
end
