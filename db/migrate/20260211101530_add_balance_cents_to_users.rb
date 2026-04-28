class AddBalanceCentsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :balance_cents, :integer, null: false, default: 0
    add_index :users, :balance_cents
  end
end
