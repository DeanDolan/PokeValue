# References I used while building this controller:
# - Rails controllers and filters:
#   https://guides.rubyonrails.org/action_controller_overview.html
# - Active Record querying and calculations:
#   https://guides.rubyonrails.org/active_record_querying.html
# - Ruby Array helpers (map, uniq, sort):
#   https://ruby-doc.org/core/Array.html

class PortfoliosController < ApplicationController
  include Authentication

  # Default list of conditions I want available in the condition filter
  # even if the user doesn't currently hold an item in that exact condition.
  DEFAULT_CONDITIONS = [
    "Mint Sealed", "Loosely Sealed", "Unsealed",
    "Big Tear", "Small Tear",
    "Big Imperfections", "Small Imperfections",
    "Pressure Marks", "Slightly Dented", "Heavy Dented", "Damaged",
    "Box Only", "Contents Only"
  ]

  def index
    if current_user
      # Pull the current user's holdings newest-first for the portfolio table
      @holdings = current_user.holdings.order(created_at: :desc)

      # Calculate high-level metrics off the holdings collection
      cost  = @holdings.sum { |h| h.total_cost.to_d }
      value = @holdings.sum { |h| h.total_value.to_d }
      pl    = value - cost
      roi   = cost.zero? ? 0 : (pl / cost * 100)

      # Build distinct lists for filters (eras, product types, conditions)
      @eras       = @holdings.map(&:era).compact.uniq.sort
      @types      = @holdings.map(&:product_type).compact.uniq.sort

      # Merge any conditions found in holdings with my default list
      # so the filter always feels complete.
      @conditions = (@holdings.map(&:condition).compact.uniq + DEFAULT_CONDITIONS).uniq.sort
    else
      # If user is not logged in, keep everything empty so the view
      # can show the "logged-out" state and avoid hitting the DB.
      @holdings   = []
      cost = value = pl = roi = 0
      @eras       = []
      @types      = []
      @conditions = DEFAULT_CONDITIONS
    end

    # Expose totals as a simple hash for the "Portfolio Overview" cards
    @totals = { cost: cost, value: value, pl: pl, roi: roi }
  end
end
