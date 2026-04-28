class CommunityCommentReaction < ApplicationRecord
  KINDS = CommunityReaction::KINDS.freeze

  belongs_to :community_comment
  belongs_to :user

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :user_id, uniqueness: { scope: :community_comment_id }

  def self.label_for(kind)
    CommunityReaction.label_for(kind)
  end

  def self.emoji_for(kind)
    CommunityReaction.emoji_for(kind)
  end
end
