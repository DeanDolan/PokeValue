class EnsureSavedAddressesForAuctions < ActiveRecord::Migration[8.1]
  def up
    unless table_exists?(:saved_addresses)
      create_table :saved_addresses do |t|
        t.references :user, null: false, foreign_key: true
        t.string :label
        t.string :line1, null: false
        t.string :line2
        t.string :city, null: false
        t.string :county
        t.string :postcode
        t.string :country_code, null: false, default: "IE"
        t.timestamps
      end
    end

    add_reference :saved_addresses, :user, null: false, foreign_key: true unless column_exists?(:saved_addresses, :user_id)
    add_column :saved_addresses, :label, :string unless column_exists?(:saved_addresses, :label)
    add_column :saved_addresses, :line1, :string unless column_exists?(:saved_addresses, :line1)
    add_column :saved_addresses, :line2, :string unless column_exists?(:saved_addresses, :line2)
    add_column :saved_addresses, :city, :string unless column_exists?(:saved_addresses, :city)
    add_column :saved_addresses, :county, :string unless column_exists?(:saved_addresses, :county)
    add_column :saved_addresses, :postcode, :string unless column_exists?(:saved_addresses, :postcode)
    add_column :saved_addresses, :country_code, :string, default: "IE" unless column_exists?(:saved_addresses, :country_code)
  end

  def down
  end
end
