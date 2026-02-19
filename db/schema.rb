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

ActiveRecord::Schema[8.1].define(version: 2026_02_19_120000) do
  create_table "audits", force: :cascade do |t|
    t.string "action"
    t.integer "associated_id"
    t.string "associated_type"
    t.integer "auditable_id"
    t.string "auditable_type"
    t.text "audited_changes"
    t.string "comment"
    t.datetime "created_at"
    t.string "remote_address"
    t.string "request_uuid"
    t.integer "user_id"
    t.string "user_type"
    t.string "username"
    t.integer "version", default: 0
    t.index ["associated_type", "associated_id"], name: "associated_index"
    t.index ["auditable_type", "auditable_id", "version"], name: "auditable_index"
    t.index ["created_at"], name: "index_audits_on_created_at"
    t.index ["request_uuid"], name: "index_audits_on_request_uuid"
    t.index ["user_id", "user_type"], name: "user_index"
  end

  create_table "manual_consumption_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.datetime "deleted_at"
    t.decimal "kwh", precision: 10, scale: 2, null: false
    t.text "note", null: false
    t.integer "property_id", null: false
    t.bigint "recorded_by_user_id"
    t.datetime "updated_at", null: false
    t.integer "visitor_id", null: false
    t.index ["date"], name: "index_manual_consumption_entries_on_date"
    t.index ["deleted_at"], name: "index_manual_consumption_entries_on_deleted_at"
    t.index ["property_id"], name: "index_manual_consumption_entries_on_property_id"
    t.index ["recorded_by_user_id"], name: "index_manual_consumption_entries_on_recorded_by_user_id"
    t.index ["visitor_id"], name: "index_manual_consumption_entries_on_visitor_id"
  end

  create_table "meter_reading_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "event_type", null: false
    t.text "note"
    t.datetime "recorded_at", null: false
    t.bigint "recorded_by_user_id"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_meter_reading_events_on_deleted_at"
    t.index ["recorded_at"], name: "index_meter_reading_events_on_recorded_at"
    t.index ["recorded_by_user_id"], name: "index_meter_reading_events_on_recorded_by_user_id"
  end

  create_table "meter_readings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.integer "meter_id", null: false
    t.integer "meter_reading_event_id", null: false
    t.datetime "updated_at", null: false
    t.decimal "value_kwh", precision: 10, scale: 2, null: false
    t.index ["deleted_at"], name: "index_meter_readings_on_deleted_at"
    t.index ["meter_id"], name: "index_meter_readings_on_meter_id"
    t.index ["meter_reading_event_id"], name: "index_meter_readings_on_meter_reading_event_id"
  end

  create_table "meters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "label"
    t.string "meter_group"
    t.string "meter_type"
    t.integer "property_id", null: false
    t.string "unit"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_meters_on_deleted_at"
    t.index ["property_id", "meter_group"], name: "index_meters_on_property_id_and_meter_group"
    t.index ["property_id"], name: "index_meters_on_property_id"
  end

  create_table "properties", force: :cascade do |t|
    t.text "address"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_properties_on_deleted_at"
  end

  create_table "stays", force: :cascade do |t|
    t.bigint "check_in_event_id"
    t.bigint "check_out_event_id"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "note"
    t.integer "property_id", null: false
    t.datetime "updated_at", null: false
    t.integer "visitor_id", null: false
    t.index ["check_in_event_id"], name: "index_stays_on_check_in_event_id"
    t.index ["check_out_event_id"], name: "index_stays_on_check_out_event_id"
    t.index ["deleted_at"], name: "index_stays_on_deleted_at"
    t.index ["property_id"], name: "index_stays_on_property_id"
    t.index ["visitor_id"], name: "index_stays_on_visitor_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "default_visitor_id"
    t.datetime "deleted_at"
    t.string "email"
    t.string "name"
    t.string "phone_number"
    t.float "recaptcha_score"
    t.string "role"
    t.string "sms_otp_code"
    t.datetime "sms_otp_sent_at"
    t.datetime "updated_at", null: false
    t.index ["default_visitor_id"], name: "index_users_on_default_visitor_id"
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["phone_number"], name: "index_users_on_phone_number", unique: true, where: "phone_number IS NOT NULL"
  end

  create_table "visitors", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "name"
    t.text "note"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_visitors_on_deleted_at"
  end

  add_foreign_key "manual_consumption_entries", "properties"
  add_foreign_key "manual_consumption_entries", "visitors"
  add_foreign_key "meter_readings", "meter_reading_events"
  add_foreign_key "meter_readings", "meters"
  add_foreign_key "meters", "properties"
  add_foreign_key "stays", "properties"
  add_foreign_key "stays", "visitors"
  add_foreign_key "users", "visitors", column: "default_visitor_id"
end
