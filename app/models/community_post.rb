class CommunityPost < ApplicationRecord
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

  CHANNELS = CHANNEL_LABELS.keys.freeze
  MAX_BODY_LENGTH = 2000
  MAX_IMAGES = 10
  MAX_IMAGE_SIZE = 10.megabytes
  ALLOWED_IMAGE_TYPES = %w[image/png image/jpeg image/jpg image/webp image/gif].freeze

  belongs_to :user
  has_many :community_comments, -> { order(created_at: :asc) }, dependent: :destroy
  has_many :community_reactions, dependent: :destroy
  has_many_attached :images

  before_validation :normalize_body

  validates :channel, presence: true, inclusion: { in: CHANNELS }
  validates :body, length: { maximum: MAX_BODY_LENGTH }, allow_blank: true
  validate :body_or_images_present
  validate :validate_images

  def self.channel_label(channel)
    CHANNEL_LABELS[channel.to_s] || channel.to_s.humanize
  end

  private

  def normalize_body
    self.body = body.to_s.strip.presence
  end

  def body_or_images_present
    errors.add(:base, "Post cannot be blank") unless body.present? || images.attached?
  end

  def validate_images
    return unless images.attached?

    errors.add(:images, "cannot exceed #{MAX_IMAGES}") if images.count > MAX_IMAGES

    images.each do |image|
      errors.add(:images, "#{image.filename} is too large") if image.blob.byte_size > MAX_IMAGE_SIZE
      errors.add(:images, "#{image.filename} must be PNG, JPG, WEBP or GIF") unless ALLOWED_IMAGE_TYPES.include?(image.blob.content_type)
    end
  end
end
