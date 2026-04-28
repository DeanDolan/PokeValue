class ChangeMarketplaceListingsHoldingIdNullable < ActiveRecord::Migration[7.1]
  def change
    change_column_null :marketplace_listings, :holding_id, true
  end
end
