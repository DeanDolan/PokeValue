class CreateHoldings < ActiveRecord::Migration[7.1]
  def change
    create_table :holdings do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :era,         null: false
      t.string  :set_name,    null: false
      t.string  :product_type, null: false
      t.string  :condition
      t.integer :quantity,    null: false, default: 1
      t.decimal :cost_per_unit, precision: 10, scale: 2
      t.decimal :value,         precision: 10, scale: 2
      t.date    :purchase_date
      t.timestamps
    end
  end
end
