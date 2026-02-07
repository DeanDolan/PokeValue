class CreateSetOverrides < ActiveRecord::Migration[8.0]
  def change
    create_table :set_overrides do |t|
      t.string  :slug, null: false
      t.decimal :total_value, precision: 12, scale: 2
      t.integer :cards
      t.integer :secret_cards
      t.timestamps
    end

    add_index :set_overrides, :slug, unique: true
  end
end
