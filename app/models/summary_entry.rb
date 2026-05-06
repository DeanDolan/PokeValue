class SummaryEntry < ApplicationRecord
  # Links each portfolio summary row to the user who created it
  belongs_to :user

  validates :user_id, presence: true
end
