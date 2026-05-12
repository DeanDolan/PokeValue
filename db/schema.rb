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

ActiveRecord::Schema[8.1].define(version: 2026_04_27_130000) do
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

  create_table "auction_bids", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.integer "auction_id", null: false
    t.integer "bidder_id", null: false
    t.datetime "created_at", null: false
    t.integer "saved_address_id", null: false
    t.datetime "updated_at", null: false
    t.index ["auction_id", "amount_cents"], name: "index_auction_bids_on_auction_id_and_amount_cents"
    t.index ["auction_id", "bidder_id"], name: "index_auction_bids_on_auction_id_and_bidder_id"
    t.index ["auction_id"], name: "index_auction_bids_on_auction_id"
    t.index ["bidder_id"], name: "index_auction_bids_on_bidder_id"
    t.index ["saved_address_id"], name: "index_auction_bids_on_saved_address_id"
  end

  create_table "auctions", force: :cascade do |t|
    t.text "auction_description", null: false
    t.string "auction_length_label"
    t.integer "auction_length_seconds"
    t.integer "bids_count", default: 0, null: false
    t.string "condition", null: false
    t.datetime "created_at", null: false
    t.datetime "ends_at", null: false
    t.datetime "payment_confirmed_at"
    t.datetime "payment_verified_at"
    t.integer "reserve_cents"
    t.string "reserve_status", default: "No Reserve", null: false
    t.integer "seller_id", null: false
    t.datetime "settled_at"
    t.string "status", default: "running", null: false
    t.datetime "updated_at", null: false
    t.text "winner_revolut_tag_encrypted"
    t.text "winning_address_text"
    t.integer "winning_bid_cents"
    t.integer "winning_bidder_id"
    t.index ["ends_at"], name: "index_auctions_on_ends_at"
    t.index ["seller_id"], name: "index_auctions_on_seller_id"
    t.index ["status"], name: "index_auctions_on_status"
    t.index ["winning_bidder_id"], name: "index_auctions_on_winning_bidder_id"
  end

  create_table "community_comment_reactions", force: :cascade do |t|
    t.integer "community_comment_id", null: false
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["community_comment_id", "kind"], name: "index_comment_reactions_on_comment_and_kind"
    t.index ["community_comment_id", "user_id"], name: "index_comment_reactions_on_comment_and_user", unique: true
    t.index ["community_comment_id"], name: "index_community_comment_reactions_on_community_comment_id"
    t.index ["user_id"], name: "index_community_comment_reactions_on_user_id"
  end

  create_table "community_comments", force: :cascade do |t|
    t.text "body", null: false
    t.integer "community_post_id", null: false
    t.datetime "created_at", null: false
    t.integer "parent_comment_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["community_post_id", "created_at"], name: "index_community_comments_on_community_post_id_and_created_at"
    t.index ["community_post_id"], name: "index_community_comments_on_community_post_id"
    t.index ["parent_comment_id"], name: "index_community_comments_on_parent_comment_id"
    t.index ["user_id"], name: "index_community_comments_on_user_id"
  end

  create_table "community_posts", force: :cascade do |t|
    t.text "body"
    t.string "channel", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["channel", "created_at"], name: "index_community_posts_on_channel_and_created_at"
    t.index ["user_id"], name: "index_community_posts_on_user_id"
  end

  create_table "community_reactions", force: :cascade do |t|
    t.integer "community_post_id", null: false
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["community_post_id", "kind"], name: "index_community_reactions_on_community_post_id_and_kind"
    t.index ["community_post_id", "user_id"], name: "index_community_reactions_on_community_post_id_and_user_id", unique: true
    t.index ["community_post_id"], name: "index_community_reactions_on_community_post_id"
    t.index ["user_id"], name: "index_community_reactions_on_user_id"
  end

  create_table "holdings", force: :cascade do |t|
    t.string "condition"
    t.decimal "cost_per_unit", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.string "era"
    t.string "image"
    t.integer "listed_quantity", default: 0, null: false
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
    t.index ["listed_quantity"], name: "index_holdings_on_listed_quantity"
    t.index ["product_id"], name: "index_holdings_on_product_id"
    t.index ["user_id"], name: "index_holdings_on_user_id"
  end

  create_table "marketplace_addresses", force: :cascade do |t|
    t.string "city"
    t.string "country_code"
    t.string "county"
    t.datetime "created_at", null: false
    t.string "line1"
    t.string "line2"
    t.string "name"
    t.string "postcode"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_marketplace_addresses_on_user_id"
  end

  create_table "marketplace_listings", force: :cascade do |t|
    t.string "condition", null: false
    t.string "country_code", null: false
    t.datetime "created_at", null: false
    t.integer "holding_id"
    t.integer "price_cents", null: false
    t.string "product_sku", null: false
    t.string "product_type_name"
    t.integer "quantity", null: false
    t.string "route_type"
    t.integer "seller_id", null: false
    t.string "set_name"
    t.string "set_slug"
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["holding_id"], name: "index_marketplace_listings_on_holding_id"
    t.index ["seller_id", "status"], name: "index_marketplace_listings_on_seller_id_and_status"
    t.index ["seller_id"], name: "index_marketplace_listings_on_seller_id"
    t.index ["status"], name: "index_marketplace_listings_on_status"
  end

  create_table "marketplace_offers", force: :cascade do |t|
    t.datetime "accepted_at"
    t.integer "buyer_id", null: false
    t.text "buyer_revolut_tag_encrypted"
    t.datetime "confirmed_paid_at"
    t.datetime "created_at", null: false
    t.integer "marketplace_listing_id", null: false
    t.integer "offer_cents", null: false
    t.datetime "paid_at"
    t.integer "seller_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["buyer_id"], name: "index_marketplace_offers_on_buyer_id"
    t.index ["marketplace_listing_id", "buyer_id", "status"], name: "idx_marketplace_offers_listing_buyer_status"
    t.index ["marketplace_listing_id"], name: "index_marketplace_offers_on_marketplace_listing_id"
    t.index ["seller_id"], name: "index_marketplace_offers_on_seller_id"
    t.index ["status"], name: "index_marketplace_offers_on_status"
  end

  create_table "marketplace_purchases", force: :cascade do |t|
    t.integer "buyer_id", null: false
    t.string "condition"
    t.datetime "created_at", null: false
    t.text "debug_context"
    t.string "debug_id"
    t.string "era"
    t.integer "holding_id"
    t.integer "marketplace_listing_id", null: false
    t.string "product_name"
    t.integer "quantity", default: 1, null: false
    t.integer "realised_pl_cents"
    t.string "route_type"
    t.integer "seller_cost_per_unit_cents"
    t.integer "seller_id", null: false
    t.string "set_name"
    t.string "set_slug"
    t.integer "total_price_cents", default: 0, null: false
    t.integer "unit_price_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["buyer_id"], name: "index_marketplace_purchases_on_buyer_id"
    t.index ["created_at"], name: "index_marketplace_purchases_on_created_at"
    t.index ["holding_id"], name: "index_marketplace_purchases_on_holding_id"
    t.index ["marketplace_listing_id"], name: "index_marketplace_purchases_on_marketplace_listing_id"
    t.index ["seller_id"], name: "index_marketplace_purchases_on_seller_id"
  end

  create_table "marketplace_transactions", force: :cascade do |t|
    t.integer "buyer_id", null: false
    t.datetime "created_at", null: false
    t.integer "marketplace_listing_id", null: false
    t.integer "quantity", null: false
    t.integer "seller_id", null: false
    t.integer "total_cents", null: false
    t.integer "unit_price_cents", null: false
    t.datetime "updated_at", null: false
    t.index ["buyer_id", "created_at"], name: "index_marketplace_transactions_on_buyer_id_and_created_at"
    t.index ["buyer_id"], name: "index_marketplace_transactions_on_buyer_id"
    t.index ["marketplace_listing_id"], name: "index_marketplace_transactions_on_marketplace_listing_id"
    t.index ["seller_id", "created_at"], name: "index_marketplace_transactions_on_seller_id_and_created_at"
    t.index ["seller_id"], name: "index_marketplace_transactions_on_seller_id"
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

  create_table "raffle_tickets", force: :cascade do |t|
    t.integer "amount_paid_cents", default: 0, null: false
    t.string "assigned_name"
    t.string "assignment_reason"
    t.datetime "created_at", null: false
    t.boolean "paid", default: false, null: false
    t.datetime "paid_at"
    t.integer "raffle_id", null: false
    t.string "revolut_tag"
    t.integer "ticket_number", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.boolean "verified", default: false, null: false
    t.datetime "verified_at"
    t.index ["created_at"], name: "index_raffle_tickets_on_created_at"
    t.index ["paid"], name: "index_raffle_tickets_on_paid"
    t.index ["raffle_id", "ticket_number"], name: "index_raffle_tickets_on_raffle_id_and_ticket_number", unique: true
    t.index ["raffle_id", "user_id"], name: "index_raffle_tickets_on_raffle_id_and_user_id"
    t.index ["raffle_id"], name: "index_raffle_tickets_on_raffle_id"
    t.index ["user_id"], name: "index_raffle_tickets_on_user_id"
  end

  create_table "raffles", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "ended_at"
    t.integer "host_id", null: false
    t.integer "main_raffle_id"
    t.string "raffle_kind", null: false
    t.string "revolut_tag"
    t.string "status", default: "active", null: false
    t.integer "ticket_price_cents", null: false
    t.string "title", null: false
    t.integer "total_tickets", null: false
    t.datetime "updated_at", null: false
    t.string "winner_name"
    t.integer "winner_number"
    t.integer "winner_user_id"
    t.index ["created_at"], name: "index_raffles_on_created_at"
    t.index ["host_id"], name: "index_raffles_on_host_id"
    t.index ["main_raffle_id"], name: "index_raffles_on_main_raffle_id"
    t.index ["raffle_kind", "status"], name: "index_raffles_on_raffle_kind_and_status"
    t.index ["raffle_kind"], name: "index_raffles_on_raffle_kind"
    t.index ["status"], name: "index_raffles_on_status"
    t.index ["winner_user_id"], name: "index_raffles_on_winner_user_id"
  end

  create_table "reviews", force: :cascade do |t|
    t.text "comment"
    t.datetime "created_at", null: false
    t.decimal "rating", precision: 2, scale: 1, null: false
    t.integer "reviewer_id", null: false
    t.integer "seller_id", null: false
    t.datetime "updated_at", null: false
    t.index ["reviewer_id", "created_at"], name: "index_reviews_on_reviewer_id_and_created_at"
    t.index ["reviewer_id"], name: "index_reviews_on_reviewer_id"
    t.index ["seller_id", "created_at"], name: "index_reviews_on_seller_id_and_created_at"
    t.index ["seller_id"], name: "index_reviews_on_seller_id"
  end

  create_table "saved_addresses", force: :cascade do |t|
    t.string "city"
    t.string "country_code"
    t.string "county"
    t.datetime "created_at", null: false
    t.string "label"
    t.string "line1"
    t.string "line2"
    t.string "name"
    t.string "postcode"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "line1", "postcode", "country_code"], name: "idx_saved_addresses_dedupe"
    t.index ["user_id"], name: "index_saved_addresses_on_user_id"
  end

  create_table "set_overrides", force: :cascade do |t|
    t.integer "cards"
    t.datetime "created_at", null: false
    t.integer "secret_cards"
    t.string "slug", null: false
    t.decimal "total_value", precision: 12, scale: 2
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_set_overrides_on_slug", unique: true
  end

  create_table "summary_entries", force: :cascade do |t|
    t.string "action", null: false
    t.string "condition"
    t.decimal "cost_per_unit", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.string "era"
    t.string "image_url"
    t.string "product_type"
    t.date "purchase_date"
    t.integer "quantity"
    t.string "set_name"
    t.string "set_slug"
    t.string "type_code"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.decimal "value", precision: 10, scale: 2
    t.index ["user_id", "created_at"], name: "index_summary_entries_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_summary_entries_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin"
    t.integer "balance_cents", default: 0, null: false
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
    t.text "revolut_tag_encrypted"
    t.datetime "updated_at", null: false
    t.string "username"
    t.index ["balance_cents"], name: "index_users_on_balance_cents"
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

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "admin_audits", "users"
  add_foreign_key "auction_bids", "auctions"
  add_foreign_key "auction_bids", "saved_addresses"
  add_foreign_key "auction_bids", "users", column: "bidder_id"
  add_foreign_key "auctions", "users", column: "seller_id"
  add_foreign_key "auctions", "users", column: "winning_bidder_id"
  add_foreign_key "community_comment_reactions", "community_comments"
  add_foreign_key "community_comment_reactions", "users"
  add_foreign_key "community_comments", "community_comments", column: "parent_comment_id"
  add_foreign_key "community_comments", "community_posts"
  add_foreign_key "community_comments", "users"
  add_foreign_key "community_posts", "users"
  add_foreign_key "community_reactions", "community_posts"
  add_foreign_key "community_reactions", "users"
  add_foreign_key "holdings", "products"
  add_foreign_key "holdings", "users"
  add_foreign_key "marketplace_addresses", "users"
  add_foreign_key "marketplace_listings", "holdings"
  add_foreign_key "marketplace_listings", "users", column: "seller_id"
  add_foreign_key "marketplace_offers", "marketplace_listings"
  add_foreign_key "marketplace_offers", "users", column: "buyer_id"
  add_foreign_key "marketplace_offers", "users", column: "seller_id"
  add_foreign_key "marketplace_transactions", "marketplace_listings"
  add_foreign_key "marketplace_transactions", "users", column: "buyer_id"
  add_foreign_key "marketplace_transactions", "users", column: "seller_id"
  add_foreign_key "raffle_tickets", "raffles"
  add_foreign_key "raffle_tickets", "users"
  add_foreign_key "raffles", "raffles", column: "main_raffle_id"
  add_foreign_key "raffles", "users", column: "host_id"
  add_foreign_key "raffles", "users", column: "winner_user_id"
  add_foreign_key "reviews", "users", column: "reviewer_id"
  add_foreign_key "reviews", "users", column: "seller_id"
  add_foreign_key "saved_addresses", "users"
  add_foreign_key "summary_entries", "users"
  add_foreign_key "watchlists", "users"
end
