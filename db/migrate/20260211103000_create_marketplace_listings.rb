class CreateMarketplaceListings < ActiveRecord::Migration[7.1]
  def change
    create_table :marketplace_listings do |t|
      t.references :seller, null: false, foreign_key: { to_table: :users }
      t.references :holding, null: false, foreign_key: true

      t.string  :product_sku, null: false
      t.string  :set_slug
      t.string  :route_type
      t.string  :set_name
      t.string  :product_type_name

      t.string  :condition, null: false
      t.string  :country_code, null: false

      t.integer :price_cents, null: false
      t.integer :quantity, null: false

      t.string  :status, null: false, default: "active"

      t.timestamps
    end

    add_index :marketplace_listings, :status
    add_index :marketplace_listings, [ :seller_id, :status ]
  end
end
