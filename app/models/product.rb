# References:
# - Active Record basics:
#   https://guides.rubyonrails.org/active_record_basics.html
# - Active Record associations:
#   https://guides.rubyonrails.org/association_basics.html
# - Active Record validations:
#   https://guides.rubyonrails.org/active_record_validations.html

class Product < ApplicationRecord
  # Link holdings to a product; if a product is removed,
  # I keep the holdings but clear their product_id
  has_many :holdings, dependent: :nullify

  # Basic sanity checks so every product has a unique sku and a name
  validates :sku,  presence: true, uniqueness: true
  validates :name, presence: true

  # Helper to grab the set slug from the sku format "set_slug:type_code"
  def set_slug
    sku.to_s.split(":", 2).first
  end

  # Helper to grab the type code from the same sku format
  def type_code
    sku.to_s.split(":", 2).last
  end
end
