class CreateCommunityCommentReactions < ActiveRecord::Migration[8.1]
  def change
    create_table :community_comment_reactions do |t|
      t.references :community_comment, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false

      t.timestamps
    end

    add_index :community_comment_reactions, [ :community_comment_id, :user_id ], unique: true, name: "index_comment_reactions_on_comment_and_user"
    add_index :community_comment_reactions, [ :community_comment_id, :kind ], name: "index_comment_reactions_on_comment_and_kind"
  end
end
