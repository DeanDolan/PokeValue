class CreateCommunityReactions < ActiveRecord::Migration[8.1]
  def change
    create_table :community_reactions do |t|
      t.references :community_post, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false

      t.timestamps
    end

    add_index :community_reactions, [ :community_post_id, :user_id ], unique: true
    add_index :community_reactions, [ :community_post_id, :kind ]
  end
end
