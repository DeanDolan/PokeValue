class CreateMarketplaceAddresses < ActiveRecord::Migration[8.1]
  def change
    create_table :marketplace_addresses do |t|
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
  end
end
