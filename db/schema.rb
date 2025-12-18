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

ActiveRecord::Schema[8.1].define(version: 2025_12_10_214804) do
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
    t.string "password_digest"
    t.string "recovery_answer_digest"
    t.string "recovery_question"
    t.datetime "updated_at", null: false
    t.string "username"
  end

  add_foreign_key "holdings", "products"
  add_foreign_key "holdings", "users"
end
