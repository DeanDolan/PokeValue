class AddMainRaffleIdToRaffles < ActiveRecord::Migration[8.1]
  def change
    add_column :raffles, :main_raffle_id, :integer
    add_index :raffles, :main_raffle_id
    add_foreign_key :raffles, :raffles, column: :main_raffle_id
  end
end
