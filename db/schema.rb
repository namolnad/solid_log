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

ActiveRecord::Schema[8.0].define(version: 20251222000006) do
  create_table "solid_log_raw", force: :cascade do |t|
    t.text "payload", null: false
    t.integer "token_id"
    t.boolean "parsed", default: false, null: false
    t.datetime "received_at", null: false
    t.datetime "parsed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["parsed", "received_at"], name: "idx_raw_unparsed"
    t.index ["received_at"], name: "idx_raw_received"
    t.index ["token_id"], name: "idx_raw_token"
  end

  create_table "solid_log_entries", force: :cascade do |t|
    t.integer "raw_id", null: false
    t.datetime "created_at", null: false
    t.string "level", null: false
    t.string "app"
    t.string "env"
    t.text "message"
    t.string "request_id"
    t.string "job_id"
    t.float "duration"
    t.integer "status_code"
    t.string "controller"
    t.string "action"
    t.string "path"
    t.string "method"
    t.text "extra_fields"
    t.index ["app", "env", "created_at"], name: "idx_entries_app_env_time", order: { created_at: :desc }
    t.index ["created_at"], name: "idx_entries_timestamp", order: :desc
    t.index ["job_id"], name: "idx_entries_job"
    t.index ["level"], name: "idx_entries_level"
    t.index ["raw_id"], name: "idx_entries_raw"
    t.index ["request_id"], name: "idx_entries_request"
  end

  create_table "solid_log_fields", force: :cascade do |t|
    t.string "name", null: false
    t.string "field_type", null: false
    t.string "filter_type", default: "multiselect", null: false
    t.integer "usage_count", default: 0, null: false
    t.datetime "last_seen_at"
    t.boolean "promoted", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "idx_fields_name", unique: true
    t.index ["promoted"], name: "idx_fields_promoted"
    t.index ["usage_count"], name: "idx_fields_usage"
  end

  create_table "solid_log_tokens", force: :cascade do |t|
    t.string "name", null: false
    t.string "token_hash", null: false
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "idx_tokens_name"
    t.index ["token_hash"], name: "idx_tokens_hash", unique: true
  end

  create_table "solid_log_facet_cache", force: :cascade do |t|
    t.string "key_name", null: false
    t.text "facet_data"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "idx_facet_expires"
    t.index ["key_name"], name: "idx_facet_key_name", unique: true
  end
end
