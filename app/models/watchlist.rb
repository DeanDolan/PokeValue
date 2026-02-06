class Watchlist < ApplicationRecord
  belongs_to :user

  validates :product_sku,
            presence: true,
            length: { maximum: 255 },
            format: { with: /\A[a-zA-Z0-9\-_]+:[a-zA-Z0-9\-_]+(?:--[a-zA-Z0-9\-_]+)*\z/ }

  validates :user_id, presence: true
end
