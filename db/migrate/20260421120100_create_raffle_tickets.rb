class CreateRaffleTickets < ActiveRecord::Migration[8.1]
  def change
    create_table :raffle_tickets do |t|
      t.references :raffle, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :assigned_name
      t.integer :ticket_number, null: false
      t.boolean :paid, null: false, default: false
      t.datetime :paid_at
      t.integer :amount_paid_cents, null: false, default: 0

      t.timestamps
    end

    add_index :raffle_tickets, [ :raffle_id, :ticket_number ], unique: true
    add_index :raffle_tickets, [ :raffle_id, :user_id ]
    add_index :raffle_tickets, :paid
    add_index :raffle_tickets, :created_at
  end
end
