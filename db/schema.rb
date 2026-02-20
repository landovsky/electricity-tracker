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

ActiveRecord::Schema[8.1].define(version: 2026_02_20_195131) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

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

  create_table "meter_photo_detections", force: :cascade do |t|
    t.float "confidence"
    t.datetime "created_at", null: false
    t.decimal "detected_value", precision: 10, scale: 2
    t.text "error_message"
    t.json "llm_response"
    t.integer "meter_id"
    t.integer "property_id", null: false
    t.text "raw_ocr_text"
    t.string "session_id", null: false
    t.string "status", default: "processing", null: false
    t.datetime "updated_at", null: false
    t.index ["meter_id"], name: "index_meter_photo_detections_on_meter_id"
    t.index ["property_id"], name: "index_meter_photo_detections_on_property_id"
    t.index ["session_id"], name: "index_meter_photo_detections_on_session_id"
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
    t.string "identifier"
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
    t.string "subdomain"
    t.string "tracking_mode", default: "visitors", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_properties_on_deleted_at"
    t.index ["subdomain"], name: "index_properties_on_subdomain"
  end

  create_table "property_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "property_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["property_id", "user_id"], name: "index_property_users_on_property_id_and_user_id", unique: true
    t.index ["property_id"], name: "index_property_users_on_property_id"
    t.index ["user_id"], name: "index_property_users_on_user_id"
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
    t.integer "property_id", null: false
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_visitors_on_deleted_at"
    t.index ["property_id"], name: "index_visitors_on_property_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "manual_consumption_entries", "properties"
  add_foreign_key "manual_consumption_entries", "visitors"
  add_foreign_key "meter_photo_detections", "meters"
  add_foreign_key "meter_photo_detections", "properties"
  add_foreign_key "meter_readings", "meter_reading_events"
  add_foreign_key "meter_readings", "meters"
  add_foreign_key "meters", "properties"
  add_foreign_key "property_users", "properties"
  add_foreign_key "property_users", "users"
  add_foreign_key "stays", "properties"
  add_foreign_key "stays", "visitors"
  add_foreign_key "users", "visitors", column: "default_visitor_id"
  add_foreign_key "visitors", "properties"
end
