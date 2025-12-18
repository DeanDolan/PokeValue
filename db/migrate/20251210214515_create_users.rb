class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :username
      t.string :email
      t.string :country_code
      t.string :recovery_question
      t.string :recovery_answer_digest
      t.string :password_digest
      t.boolean :admin
      t.integer :failed_attempts
      t.datetime :locked_at

      t.timestamps
    end
  end
end
