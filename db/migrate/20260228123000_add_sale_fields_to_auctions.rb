class AddSaleFieldsToAuctions < ActiveRecord::Migration[8.1]
  def up
    add_reference :auctions, :winning_bidder, foreign_key: { to_table: :users } unless column_exists?(:auctions, :winning_bidder_id)
    add_column :auctions, :winning_bid_cents, :integer unless column_exists?(:auctions, :winning_bid_cents)
    add_column :auctions, :winning_address_text, :text unless column_exists?(:auctions, :winning_address_text)
    add_column :auctions, :settled_at, :datetime unless column_exists?(:auctions, :settled_at)
  end

  def down
  end
end
