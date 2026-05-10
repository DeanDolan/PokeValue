class CommunityComment < ApplicationRecord
  MAX_BODY_LENGTH = 1000

  belongs_to :community_post
  belongs_to :user
  belongs_to :parent_comment, class_name: "CommunityComment", optional: true
  has_many :replies, -> { order(created_at: :asc) }, class_name: "CommunityComment", foreign_key: :parent_comment_id, dependent: :destroy
  has_many :community_comment_reactions, dependent: :destroy

  before_validation :normalize_body

  validates :body, presence: true, length: { maximum: MAX_BODY_LENGTH }
  validate :parent_comment_must_belong_to_same_post

  private

  def normalize_body
    self.body = body.to_s.strip.presence
  end

  def parent_comment_must_belong_to_same_post
    errors.add(:parent_comment_id, "is invalid") if parent_comment.present? && parent_comment.community_post_id != community_post_id
  end
end
