class Review < ApplicationRecord
  belongs_to :seller, class_name: "User"
  belongs_to :reviewer, class_name: "User"

  validates :rating, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }

  validate :rating_step

  private

  def rating_step
    r = rating.to_f
    ok = ((r * 2) % 1).zero?
    errors.add(:rating, "must be in 0.5 steps") unless ok
  end
end
