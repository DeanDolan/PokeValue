class AddAdminMfaToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :mfa_enabled, :boolean, default: false, null: false
    add_column :users, :mfa_secret_encrypted, :text
    add_column :users, :mfa_last_used_step, :bigint
    add_column :users, :mfa_failed_attempts, :integer, default: 0, null: false
    add_column :users, :mfa_locked_at, :datetime
    add_column :users, :mfa_recovery_codes_digest, :text
  end
end
