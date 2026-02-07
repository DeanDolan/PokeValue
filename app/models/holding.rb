class Holding < ApplicationRecord
  belongs_to :user
  belongs_to :product

  before_save :recalculate_totals

  def pl
    (total_value || 0).to_d - (total_cost || 0).to_d
  end

  def roi_pct
    tc = (total_cost || 0).to_d
    return 0 if tc.zero?
    (pl / tc * 100)
  end

  private

  def recalculate_totals
    q   = quantity.to_i
    cpu = (cost_per_unit || 0).to_d
    v   = (value || 0).to_d

    self.total_cost  = q * cpu
    self.total_value = q * v
  end
end
