class Watchlist < ApplicationRecord
  # Connects each watchlist item to the user who saved it
  belongs_to :user

  # Stores the watched product SKU and keeps it in the app's expected SKU format
  validates :product_sku,
            presence: true,
            length: { maximum: 255 },
            format: { with: /\A[a-zA-Z0-9\-_]+:[a-zA-Z0-9\-_]+(?:--[a-zA-Z0-9\-_]+)*\z/ }

  # Makes sure every watchlist record belongs to a user
  validates :user_id, presence: true
end
