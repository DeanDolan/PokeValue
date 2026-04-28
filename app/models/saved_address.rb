class SavedAddress < ApplicationRecord
  belongs_to :user
  has_many :auction_bids, dependent: :nullify

  validates :line1, presence: true
  validates :city, presence: true
  validates :country_code, presence: true

  validate :max_five_addresses, on: :create

  def display_label
    custom_label =
      if has_attribute?(:label)
        self[:label].to_s
      else
        ""
      end

    custom_label.presence || line1.to_s.presence || "Saved Address"
  end

  def single_line
    [ line1, line2.presence, city, county.presence, postcode.presence, country_code ].compact.join(", ")
  end

  private

  def max_five_addresses
    return unless user
    return if SavedAddress.where(user_id: user.id).where.not(id: id).count < 5

    errors.add(:base, "You can save up to 5 addresses")
  end
end
