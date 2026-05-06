class Review < ApplicationRecord
  # Connects each review to the seller being reviewed.
  belongs_to :seller, class_name: "User"

  # Connects each review to the user who wrote the review.
  belongs_to :reviewer, class_name: "User"

  # Allows ratings from 0 to 5 with one decimal place.
  validates :rating, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }
  validates :comment, length: { maximum: 1000 }, allow_blank: true

  validate :rating_one_decimal_place

  private

  # Checks that ratings use no more than one decimal place.
  def rating_one_decimal_place
    return if rating.blank?

    text = rating.to_s
    decimal = text.split(".", 2)[1].to_s
    errors.add(:rating, "must use one decimal place or less") if decimal.length > 1
  end
end
