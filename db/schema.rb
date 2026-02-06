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

ActiveRecord::Schema[8.1].define(version: 2026_01_31_190000) do
  create_table "admin_audits", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip"
    t.decimal "new_value", precision: 12, scale: 2, null: false
    t.decimal "old_value", precision: 12, scale: 2
    t.string "sku", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.integer "user_id", null: false
    t.index ["sku"], name: "index_admin_audits_on_sku"
    t.index ["user_id"], name: "index_admin_audits_on_user_id"
  end

  create_table "holdings", force: :cascade do |t|
    t.string "condition"
    t.decimal "cost_per_unit", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.string "era"
    t.string "image"
    t.decimal "pl", precision: 12, scale: 2, default: "0.0", null: false
    t.integer "product_id", null: false
    t.string "product_type"
    t.date "purchase_date"
    t.integer "quantity", default: 0, null: false
    t.decimal "roi_pct", precision: 7, scale: 2, default: "0.0", null: false
    t.string "set_name"
    t.decimal "total_cost", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "total_value", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "username"
    t.decimal "value", precision: 10, scale: 2, default: "0.0", null: false
    t.index ["product_id"], name: "index_holdings_on_product_id"
    t.index ["user_id", "product_id"], name: "index_holdings_on_user_id_and_product_id", unique: true, where: "product_id IS NOT NULL"
    t.index ["user_id"], name: "index_holdings_on_user_id"
  end

  create_table "products", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "era"
    t.string "image"
    t.string "name"
    t.string "product_type"
    t.string "set_name"
    t.string "sku"
    t.datetime "updated_at", null: false
    t.decimal "value", precision: 10, scale: 2, default: "0.0", null: false
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin"
    t.string "country_code"
    t.datetime "created_at", null: false
    t.string "email"
    t.integer "failed_attempts"
    t.datetime "locked_at"
    t.boolean "mfa_enabled", default: false, null: false
    t.integer "mfa_failed_attempts", default: 0, null: false
    t.bigint "mfa_last_used_step"
    t.datetime "mfa_locked_at"
    t.text "mfa_recovery_codes_digest"
    t.text "mfa_secret_encrypted"
    t.string "password_digest"
    t.string "recovery_answer_digest"
    t.string "recovery_question"
    t.datetime "updated_at", null: false
    t.string "username"
  end

  create_table "watchlists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "product_sku", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["product_sku"], name: "index_watchlists_on_product_sku"
    t.index ["user_id", "product_sku"], name: "index_watchlists_on_user_id_and_product_sku", unique: true
    t.index ["user_id"], name: "index_watchlists_on_user_id"
  end

  add_foreign_key "admin_audits", "users"
  add_foreign_key "holdings", "products"
  add_foreign_key "holdings", "users"
  add_foreign_key "watchlists", "users"
end
