class CommunityComment < ApplicationRecord
  # Limits comment length so community threads stay readable
  MAX_BODY_LENGTH = 1000

  # Each comment belongs to one post and one user
  belongs_to :community_post
  belongs_to :user

  # Allows a comment to be a reply to another comment
  belongs_to :parent_comment, class_name: "CommunityComment", optional: true

  # Loads replies in oldest-first order and removes them if the parent comment is deleted
  has_many :replies, -> { order(created_at: :asc) }, class_name: "CommunityComment", foreign_key: :parent_comment_id, dependent: :destroy

  # Removes comment reactions when the comment is deleted
  has_many :community_comment_reactions, dependent: :destroy

  # Cleans up the comment text before Rails runs validations
  before_validation :normalize_body

  # Requires comment text and limits the maximum length
  validates :body, presence: true, length: { maximum: MAX_BODY_LENGTH }

  # Prevents replies being attached to comments from a different post
  validate :parent_comment_must_belong_to_same_post

  private

  # Strips extra spaces and turns blank text into nil so presence validation works properly
  def normalize_body
    self.body = body.to_s.strip.presence
  end

  # Keeps nested replies inside the same community post
  def parent_comment_must_belong_to_same_post
    return if parent_comment.blank?
    return if parent_comment.community_post_id == community_post_id

    errors.add(:parent_comment_id, "is invalid")
  end
end
