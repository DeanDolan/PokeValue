class CreateAuctions < ActiveRecord::Migration[8.1]
  def change
    create_table :auctions do |t|
      t.references :seller, null: false, foreign_key: { to_table: :users }
      t.text :auction_description, null: false
      t.string :condition, null: false
      t.string :reserve_status, null: false, default: "No Reserve"
      t.integer :reserve_cents
      t.datetime :ends_at, null: false
      t.string :auction_length_label
      t.integer :auction_length_seconds
      t.string :status, null: false, default: "running"
      t.integer :bids_count, null: false, default: 0

      t.timestamps
    end

    add_index :auctions, :status
    add_index :auctions, :ends_at
  end
end
