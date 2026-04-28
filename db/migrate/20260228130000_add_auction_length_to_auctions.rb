class AddAuctionLengthToAuctions < ActiveRecord::Migration[8.1]
  def change
    add_column :auctions, :auction_length_label, :string unless column_exists?(:auctions, :auction_length_label)
    add_column :auctions, :auction_length_seconds, :integer unless column_exists?(:auctions, :auction_length_seconds)
  end
end
