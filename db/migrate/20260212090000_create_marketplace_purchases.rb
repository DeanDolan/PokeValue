class CreateMarketplacePurchases < ActiveRecord::Migration[8.0]
  def change
    create_table :marketplace_purchases do |t|
      t.integer :buyer_id, null: false
      t.integer :seller_id, null: false
      t.integer :marketplace_listing_id, null: false
      t.integer :holding_id

      t.string  :set_slug
      t.string  :route_type
      t.string  :product_name
      t.string  :era
      t.string  :set_name
      t.string  :condition

      t.integer :quantity, null: false, default: 1

      t.integer :unit_price_cents, null: false, default: 0
      t.integer :total_price_cents, null: false, default: 0

      t.integer :seller_cost_per_unit_cents
      t.integer :realised_pl_cents

      t.string  :debug_id
      t.text    :debug_context

      t.timestamps
    end

    add_index :marketplace_purchases, :buyer_id
    add_index :marketplace_purchases, :seller_id
    add_index :marketplace_purchases, :marketplace_listing_id
    add_index :marketplace_purchases, :holding_id
    add_index :marketplace_purchases, :created_at
  end
end
