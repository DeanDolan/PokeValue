class CreateRaffles < ActiveRecord::Migration[8.1]
  def change
    create_table :raffles do |t|
      t.references :host, null: false, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.string :raffle_kind, null: false
      t.integer :ticket_price_cents, null: false
      t.integer :total_tickets, null: false
      t.string :status, null: false, default: "active"
      t.integer :winner_number
      t.string :winner_name
      t.references :winner_user, foreign_key: { to_table: :users }
      t.datetime :completed_at
      t.datetime :ended_at

      t.timestamps
    end

    add_index :raffles, :status
    add_index :raffles, :raffle_kind
    add_index :raffles, [ :raffle_kind, :status ]
    add_index :raffles, :created_at
  end
end
