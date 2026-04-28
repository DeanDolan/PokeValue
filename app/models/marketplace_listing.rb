class MarketplaceListing < ApplicationRecord
  belongs_to :seller, class_name: "User"
  belongs_to :holding, optional: true

  has_many :marketplace_offers, dependent: :destroy
  has_many_attached :photos

  STATUSES = %w[active sold cancelled deleted].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :price_cents, numericality: { greater_than: 0 }
  validates :quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :country_code, presence: true
  validates :condition, presence: true
  validates :set_slug, presence: true
  validates :route_type, presence: true
  validates :product_sku, presence: true

  validate :photos_count_and_type

  scope :active, -> { where(status: "active").where("quantity > 0") }

  def active?
    status.to_s == "active" && quantity.to_i > 0
  end

  def sold?
    status.to_s == "sold"
  end

  private

  def photos_count_and_type
    return unless photos.attached?

    if photos.count > 4
      errors.add(:photos, "must be 4 images or fewer")
    end

    photos.each do |p|
      ct = p.content_type.to_s
      unless ct == "image/png" || ct == "image/jpeg" || ct == "image/jpg"
        errors.add(:photos, "must be JPG or PNG")
        break
      end
    end
  end
end
