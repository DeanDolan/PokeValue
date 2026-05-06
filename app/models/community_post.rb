class CommunityPost < ApplicationRecord
  # Stores the allowed community channels and their display names
  CHANNEL_LABELS = {
    "general" => "General",
    "item_finder" => "Item Finder",
    "found_in_the_wild" => "Found in the Wild",
    "mailday" => "Mailday",
    "collecting" => "Collecting",
    "investing" => "Investing",
    "trading" => "Trading",
    "grading" => "Grading",
    "card_shows" => "Card Shows",
    "content_creators" => "Content Creators",
    "app_suggestions" => "Application Suggestions",
    "application_problems" => "Application Problems"
  }.freeze

  # Builds the approved channel list from the channel labels
  CHANNELS = CHANNEL_LABELS.keys.freeze

  # Sets limits for post text and uploaded images
  MAX_BODY_LENGTH = 2000
  MAX_IMAGES = 10
  ALLOWED_IMAGE_TYPES = %w[image/png image/jpeg image/jpg image/webp image/gif].freeze
  MAX_IMAGE_SIZE = 10.megabytes

  # Each community post belongs to the user who created it
  belongs_to :user

  # Removes comments and reactions when the post is deleted
  has_many :community_comments, -> { order(created_at: :asc) }, dependent: :destroy
  has_many :community_reactions, dependent: :destroy

  # Allows each post to have multiple uploaded images
  has_many_attached :images

  # Cleans up the post body before validation
  before_validation :normalize_body

  # Validates channel, text length and post content rules
  validates :channel, presence: true, inclusion: { in: CHANNELS }
  validates :body, length: { maximum: MAX_BODY_LENGTH }, allow_blank: true
  validate :body_or_images_present
  validate :validate_images

  # Returns the display label for a channel
  def self.channel_label(channel)
    CHANNEL_LABELS[channel.to_s] || channel.to_s.humanize
  end

  private

  # Strips extra spaces and stores blank text as nil
  def normalize_body
    self.body = body.to_s.strip.presence
  end

  # Requires a post to contain either text or at least one image
  def body_or_images_present
    return if body.present? || images.attached?

    errors.add(:base, "Post cannot be blank")
  end

  # Checks image count, file size and file type before saving
  def validate_images
    return unless images.attached?

    if images.count > MAX_IMAGES
      errors.add(:images, "cannot exceed #{MAX_IMAGES}")
    end

    images.each do |image|
      if image.blob.byte_size > MAX_IMAGE_SIZE
        errors.add(:images, "#{image.filename} is too large")
      end

      unless ALLOWED_IMAGE_TYPES.include?(image.blob.content_type)
        errors.add(:images, "#{image.filename} must be PNG, JPG, WEBP or GIF")
      end
    end
  end
end
