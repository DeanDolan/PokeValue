class MarketplaceTransaction < ApplicationRecord
  # Transaction belongs to the listing and both users involved
  belongs_to :marketplace_listing
  belongs_to :buyer, class_name: "User"
  belongs_to :seller, class_name: "User"

  # Money is stored in cents to avoid floating point rounding issues
  validates :unit_price_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :total_cents, numericality: { only_integer: true, greater_than: 0 }
end
