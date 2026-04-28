class AddListedQuantityToHoldings < ActiveRecord::Migration[7.1]
  def change
    add_column :holdings, :listed_quantity, :integer, null: false, default: 0
    add_index :holdings, :listed_quantity
  end
end
