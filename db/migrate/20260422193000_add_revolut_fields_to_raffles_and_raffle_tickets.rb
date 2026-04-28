class AddRevolutFieldsToRafflesAndRaffleTickets < ActiveRecord::Migration[8.0]
  def change
    add_column :raffles, :revolut_tag, :string unless column_exists?(:raffles, :revolut_tag)

    add_column :raffle_tickets, :revolut_tag, :string unless column_exists?(:raffle_tickets, :revolut_tag)
    add_column :raffle_tickets, :verified, :boolean, default: false, null: false unless column_exists?(:raffle_tickets, :verified)
    add_column :raffle_tickets, :verified_at, :datetime unless column_exists?(:raffle_tickets, :verified_at)
  end
end
