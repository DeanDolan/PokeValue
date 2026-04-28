class CreateAuctionBids < ActiveRecord::Migration[8.1]
  def change
    create_table :auction_bids do |t|
      t.references :auction, null: false, foreign_key: true
      t.references :bidder, null: false, foreign_key: { to_table: :users }
      t.references :saved_address, null: false, foreign_key: true
      t.integer :amount_cents, null: false

      t.timestamps
    end

    add_index :auction_bids, [ :auction_id, :amount_cents ]
    add_index :auction_bids, [ :auction_id, :bidder_id ]
  end
end
