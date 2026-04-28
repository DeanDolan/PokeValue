class CreateMarketplaceTransactions < ActiveRecord::Migration[7.1]
  def change
    create_table :marketplace_transactions do |t|
      t.references :marketplace_listing, null: false, foreign_key: true
      t.references :buyer, null: false, foreign_key: { to_table: :users }
      t.references :seller, null: false, foreign_key: { to_table: :users }

      t.integer :unit_price_cents, null: false
      t.integer :quantity, null: false
      t.integer :total_cents, null: false

      t.timestamps
    end

    add_index :marketplace_transactions, [ :buyer_id, :created_at ]
    add_index :marketplace_transactions, [ :seller_id, :created_at ]
  end
end
