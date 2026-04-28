class AddAssignmentReasonToRaffleTickets < ActiveRecord::Migration[8.0]
  def change
    add_column :raffle_tickets, :assignment_reason, :string unless column_exists?(:raffle_tickets, :assignment_reason)
  end
end
