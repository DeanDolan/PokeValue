class CreateCommunityPosts < ActiveRecord::Migration[8.1]
  def change
    create_table :community_posts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :channel, null: false
      t.text :body

      t.timestamps
    end

    add_index :community_posts, [ :channel, :created_at ]
  end
end
