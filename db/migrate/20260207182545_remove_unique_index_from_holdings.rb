class RemoveUniqueIndexFromHoldings < ActiveRecord::Migration[7.1]
  def change
    remove_index :holdings, column: [ :user_id, :product_id ], unique: true
  end
end
