class SavedAddress < ApplicationRecord
  # Connects each saved address to one user
  belongs_to :user

  # Allows auction bids to reference a saved delivery address
  has_many :auction_bids, dependent: :nullify

  # Requires the main address line
  validates :line1, presence: true

  # Requires the town or city
  validates :city, presence: true

  # Requires the country code
  validates :country_code, presence: true

  # Limits each user to five saved addresses
  validate :max_five_addresses, on: :create

  # Shows the custom address label first, then falls back to the first address line
  def display_label
    custom_label =
      if has_attribute?(:label)
        self[:label].to_s
      else
        ""
      end

    custom_label.presence || line1.to_s.presence || "Saved Address"
  end

  # Combines the address fields into one readable address line
  def single_line
    [ line1, line2.presence, city, county.presence, postcode.presence, country_code ].compact.join(", ")
  end

  private

  # Prevents users from saving more than five delivery addresses
  def max_five_addresses
    return unless user
    return if SavedAddress.where(user_id: user.id).where.not(id: id).count < 5

    errors.add(:base, "You can save up to 5 addresses")
  end
end
