class CommunityCommentReaction < ApplicationRecord
  # Reuses the same reaction types as post reactions so comments and posts stay consistent
  KINDS = CommunityReaction::KINDS.freeze

  # Each comment reaction belongs to one comment and one user
  belongs_to :community_comment
  belongs_to :user

  # Makes sure only approved reaction types can be saved
  validates :kind, presence: true, inclusion: { in: KINDS }

  # Stops the same user from reacting more than once to the same comment
  validates :user_id, uniqueness: { scope: :community_comment_id }

  # Gets the readable label for a reaction type
  def self.label_for(kind)
    CommunityReaction.label_for(kind)
  end

  # Gets the emoji for a reaction type
  def self.emoji_for(kind)
    CommunityReaction.emoji_for(kind)
  end
end
