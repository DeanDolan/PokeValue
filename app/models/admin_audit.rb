class AdminAudit < ApplicationRecord
  belongs_to :user
  validates :sku, presence: true
end
