class AddPaymentFlowToAuctions < ActiveRecord::Migration[8.1]
  def change
    add_column :auctions, :payment_confirmed_at, :datetime
    add_column :auctions, :payment_verified_at, :datetime
    add_column :auctions, :winner_revolut_tag_encrypted, :text
  end
end
