class CreateMarketplaceOffers < ActiveRecord::Migration[8.1]
  def change
    create_table :marketplace_offers do |t|
      t.integer :marketplace_listing_id, null: false
      t.integer :buyer_id, null: false
      t.integer :seller_id, null: false
      t.integer :offer_cents, null: false
      t.string :status, null: false, default: "pending"
      t.text :buyer_revolut_tag_encrypted
      t.datetime :accepted_at
      t.datetime :paid_at
      t.datetime :confirmed_paid_at
      t.timestamps
    end

    add_index :marketplace_offers, :marketplace_listing_id
    add_index :marketplace_offers, :buyer_id
    add_index :marketplace_offers, :seller_id
    add_index :marketplace_offers, :status
    add_index :marketplace_offers, [ :marketplace_listing_id, :buyer_id, :status ], name: "idx_marketplace_offers_listing_buyer_status"

    add_foreign_key :marketplace_offers, :marketplace_listings
    add_foreign_key :marketplace_offers, :users, column: :buyer_id
    add_foreign_key :marketplace_offers, :users, column: :seller_id
  end
end
