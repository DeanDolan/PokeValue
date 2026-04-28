class CreateReviews < ActiveRecord::Migration[7.1]
  def change
    create_table :reviews do |t|
      t.references :seller, null: false, foreign_key: { to_table: :users }
      t.references :reviewer, null: false, foreign_key: { to_table: :users }
      t.decimal :rating, null: false, precision: 2, scale: 1
      t.text :comment
      t.timestamps
    end

    add_index :reviews, [ :seller_id, :created_at ]
    add_index :reviews, [ :reviewer_id, :created_at ]
  end
end
