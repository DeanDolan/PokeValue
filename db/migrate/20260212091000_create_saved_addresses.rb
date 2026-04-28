class CreateSavedAddresses < ActiveRecord::Migration[8.1]
  def change
    create_table :saved_addresses do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.string :line1
      t.string :line2
      t.string :city
      t.string :county
      t.string :postcode
      t.string :country_code
      t.timestamps
    end

    add_index :saved_addresses, [ :user_id, :line1, :postcode, :country_code ], name: "idx_saved_addresses_dedupe"
  end
end
