class AddPortfolioFieldsToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :image, :string unless column_exists?(:products, :image)
    add_column :products, :era, :string unless column_exists?(:products, :era)
    add_column :products, :set_name, :string unless column_exists?(:products, :set_name)
    add_column :products, :product_type, :string unless column_exists?(:products, :product_type)
    add_column :products, :value, :decimal, precision: 10, scale: 2, null: false, default: 0 unless column_exists?(:products, :value)
  end
end
