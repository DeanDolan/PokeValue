# References:
# - Active Record associations:
#   https://guides.rubyonrails.org/association_basics.html
# - Active Record callbacks:
#   https://guides.rubyonrails.org/active_record_callbacks.html
# - Active Record validations / numeric helpers:
#   https://guides.rubyonrails.org/active_record_validations.html

class Holding < ApplicationRecord
  # Every holding belongs to a user and a product
  belongs_to :user
  belongs_to :product

  # Keep total_cost and total_value in sync any time the record is saved
  before_save :recalculate_totals

  # Simple P/L helper in euros
  def pl
    (total_value || 0).to_d - (total_cost || 0).to_d
  end

  # ROI as a percentage (returns 0 if total_cost is 0 to avoid divide-by-zero)
  def roi_pct
    tc = (total_cost || 0).to_d
    return 0 if tc.zero?
    (pl / tc * 100)
  end

  private

  # Recalculate totals based on quantity, cost per unit and value per unit
  def recalculate_totals
    q   = quantity.to_i
    cpu = (cost_per_unit || 0).to_d
    v   = (value || 0).to_d

    self.total_cost  = q * cpu
    self.total_value = q * v
  end
end
