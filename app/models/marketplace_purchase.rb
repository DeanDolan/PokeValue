class MarketplacePurchase < ApplicationRecord
  belongs_to :listing, class_name: "MarketplaceListing", foreign_key: :marketplace_listing_id, optional: true
  belongs_to :buyer, class_name: "User", foreign_key: :buyer_id, optional: true
  belongs_to :seller, class_name: "User", foreign_key: :seller_id, optional: true
  belongs_to :holding, optional: true

  validates :buyer_id, :seller_id, :marketplace_listing_id, :quantity, :unit_price_cents, :total_price_cents, presence: true
  validates :quantity, numericality: { greater_than: 0 }

  def unit_price_eur
    unit_price_cents.to_i / 100.0
  end

  def total_price_eur
    total_price_cents.to_i / 100.0
  end

  def realised_pl_eur
    realised_pl_cents.to_i / 100.0
  end

  def seller_cost_per_unit_eur
    seller_cost_per_unit_cents.to_i / 100.0
  end
end
