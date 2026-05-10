class AdminAudit < ApplicationRecord
  # Each audit row belongs to the admin user who changed a value.
  belongs_to :user

  # The product SKU and new value are required because they identify the changed product.
  validates :sku, presence: true
  validates :new_value, presence: true

  # Creates an audit row when an admin changes a product value.
  def self.record_change!(user:, product:, old_value:, new_value:, request:)
    return if user.blank? || product.blank?

    create!(
      user: user,
      sku: product.sku.to_s,
      old_value: old_value,
      new_value: new_value,
      ip: request&.remote_ip.to_s,
      user_agent: request&.user_agent.to_s.first(1000)
    )
  rescue => e
    Rails.logger.warn("[AdminAudit] Could not record admin audit: #{e.class} #{e.message}")
    nil
  end
end
