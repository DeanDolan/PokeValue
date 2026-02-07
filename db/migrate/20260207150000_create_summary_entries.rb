class CreateSummaryEntries < ActiveRecord::Migration[7.1]
  def change
    create_table :summary_entries do |t|
      t.references :user, null: false, foreign_key: true

      t.string  :action, null: false

      t.string  :era
      t.string  :set_name
      t.string  :set_slug
      t.string  :product_type
      t.string  :type_code
      t.string  :image_url

      t.integer :quantity
      t.decimal :cost_per_unit, precision: 10, scale: 2
      t.decimal :value,         precision: 10, scale: 2

      t.date    :purchase_date
      t.string  :condition

      t.timestamps
    end

    add_index :summary_entries, [ :user_id, :created_at ]
  end
end
