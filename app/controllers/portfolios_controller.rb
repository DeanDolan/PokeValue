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
      @holdings = current_user.holdings.order(
        Arel.sql("COALESCE(purchase_date, DATE(created_at)) DESC"),
        created_at: :desc
      )

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

  def metrics
    unless current_user
      render json: { error: "not_signed_in", series: [], debug: { signed_in: false } }, status: :unauthorized
      return
    end

    response.headers["Cache-Control"] = "no-store"

    holdings = current_user.holdings.select(:id, :purchase_date, :created_at, :total_cost, :total_value).to_a
    grouped = holdings.group_by { |h| (h.purchase_date || h.created_at&.to_date) }
    dates = grouped.keys.compact.sort

    cum_cost = 0.to_d
    cum_value = 0.to_d

    series = dates.map do |d|
      day_cost = grouped[d].sum { |h| (h.total_cost || 0).to_d }
      day_value = grouped[d].sum { |h| (h.total_value || 0).to_d }

      cum_cost += day_cost
      cum_value += day_value

      pl = cum_value - cum_cost
      roi = cum_cost.zero? ? 0.to_d : (pl / cum_cost * 100)

      {
        date: d.strftime("%Y-%m-%d"),
        total_cost: cum_cost.to_f,
        total_value: cum_value.to_f,
        pl: pl.to_f,
        roi: roi.to_f
      }
    end

    render json: {
      series: series,
      debug: {
        signed_in: true,
        holdings_count: holdings.size,
        date_points: series.size
      }
    }
  end
end
