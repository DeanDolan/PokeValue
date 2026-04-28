class AddParentCommentIdToCommunityComments < ActiveRecord::Migration[8.1]
  def change
    add_reference :community_comments, :parent_comment, foreign_key: { to_table: :community_comments }
  end
end
