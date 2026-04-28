class MarketplaceOffer < ApplicationRecord
  belongs_to :marketplace_listing
  belongs_to :buyer, class_name: "User"
  belongs_to :seller, class_name: "User"

  STATUSES = %w[pending accepted paid confirmed_paid rejected cancelled].freeze

  validates :marketplace_listing_id, :buyer_id, :seller_id, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :offer_cents, numericality: { only_integer: true, greater_than: 0 }

  scope :newest_first, -> { order(created_at: :desc) }

  def offer_eur
    offer_cents.to_i / 100.0
  end

  def pending?
    status.to_s == "pending"
  end

  def accepted?
    status.to_s == "accepted"
  end

  def paid?
    status.to_s == "paid"
  end

  def confirmed_paid?
    status.to_s == "confirmed_paid"
  end

  def rejected?
    status.to_s == "rejected"
  end

  def buyer_revolut_tag
    return nil if buyer_revolut_tag_encrypted.blank?
    self.class.buyer_revolut_tag_encryptor.decrypt_and_verify(buyer_revolut_tag_encrypted)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  def buyer_revolut_tag=(plain)
    cleaned = plain.to_s.strip

    if cleaned.present?
      cleaned = "@#{cleaned}" unless cleaned.start_with?("@")
      self.buyer_revolut_tag_encrypted = self.class.buyer_revolut_tag_encryptor.encrypt_and_sign(cleaned)
    else
      self.buyer_revolut_tag_encrypted = nil
    end
  end

  def self.buyer_revolut_tag_encryptor
    key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key("marketplace_offer_buyer_revolut_tag_v1", 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm")
  end
end
