class Product < ApplicationRecord
  has_many :holdings, dependent: :nullify

  validates :sku, presence: true, uniqueness: true
  validates :name, presence: true

  def set_slug
    s = sku.to_s
    return s.split(":", 2).first if s.include?(":")
    return s.split("--", 2).first if s.include?("--")
    s
  end

  def type_code
    s = sku.to_s
    return s.split(":", 2).last if s.include?(":")
    return s.split("--", 2).last if s.include?("--")
    ""
  end
end
