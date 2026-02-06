class CreateAdminAudits < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_audits do |t|
      t.references :user, null: false, foreign_key: true
      t.string :sku, null: false
      t.decimal :old_value, precision: 12, scale: 2
      t.decimal :new_value, precision: 12, scale: 2, null: false
      t.string :ip
      t.text :user_agent
      t.timestamps
    end

    add_index :admin_audits, :sku
  end
end
