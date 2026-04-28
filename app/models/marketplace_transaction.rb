class MarketplaceTransaction < ApplicationRecord
  belongs_to :marketplace_listing
  belongs_to :buyer, class_name: "User"
  belongs_to :seller, class_name: "User"

  validates :unit_price_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :total_cents, numericality: { only_integer: true, greater_than: 0 }
end
