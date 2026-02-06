class CreateWatchlists < ActiveRecord::Migration[8.0]
  def change
    create_table :watchlists do |t|
      t.references :user, null: false, foreign_key: true
      t.string :product_sku, null: false
      t.timestamps
    end

    add_index :watchlists, [ :user_id, :product_sku ], unique: true
    add_index :watchlists, :product_sku
  end
end
