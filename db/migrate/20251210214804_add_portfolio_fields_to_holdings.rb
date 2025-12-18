class AddPortfolioFieldsToHoldings < ActiveRecord::Migration[8.0]
  def change
    add_reference :holdings, :user, null: false, foreign_key: true unless column_exists?(:holdings, :user_id)
    add_reference :holdings, :product, foreign_key: true unless column_exists?(:holdings, :product_id)

    add_column :holdings, :username, :string unless column_exists?(:holdings, :username)
    add_column :holdings, :image, :string unless column_exists?(:holdings, :image)
    add_column :holdings, :era, :string unless column_exists?(:holdings, :era)
    add_column :holdings, :set_name, :string unless column_exists?(:holdings, :set_name)
    add_column :holdings, :product_type, :string unless column_exists?(:holdings, :product_type)
    add_column :holdings, :condition, :string unless column_exists?(:holdings, :condition)

    add_column :holdings, :quantity, :integer, null: false, default: 0 unless column_exists?(:holdings, :quantity)
    add_column :holdings, :cost_per_unit, :decimal, precision: 10, scale: 2, null: false, default: 0 unless column_exists?(:holdings, :cost_per_unit)
    add_column :holdings, :purchase_date, :date unless column_exists?(:holdings, :purchase_date)

    add_column :holdings, :total_cost,  :decimal, precision: 12, scale: 2, null: false, default: 0 unless column_exists?(:holdings, :total_cost)
    add_column :holdings, :value,       :decimal, precision: 10, scale: 2, null: false, default: 0 unless column_exists?(:holdings, :value)
    add_column :holdings, :total_value, :decimal, precision: 12, scale: 2, null: false, default: 0 unless column_exists?(:holdings, :total_value)
    add_column :holdings, :pl,          :decimal, precision: 12, scale: 2, null: false, default: 0 unless column_exists?(:holdings, :pl)
    add_column :holdings, :roi_pct,     :decimal, precision: 7,  scale: 2,  null: false, default: 0 unless column_exists?(:holdings, :roi_pct)

    add_index :holdings, [ :user_id, :product_id ], unique: true, where: "product_id IS NOT NULL" unless index_exists?(:holdings, [ :user_id, :product_id ])
  end
end
