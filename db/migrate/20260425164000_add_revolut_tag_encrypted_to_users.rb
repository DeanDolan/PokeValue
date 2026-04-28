class AddRevolutTagEncryptedToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :revolut_tag_encrypted, :text
  end
end
