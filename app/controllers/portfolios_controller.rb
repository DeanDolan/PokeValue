class PortfoliosController < ApplicationController
  include Authentication

  # Default condition options used by the portfolio condition filter.
  DEFAULT_CONDITIONS = [
    "Mint Sealed",
    "Loosely Sealed",
    "Mini Tear/Hole (<2cm)",
    "Unsealed",
    "Small Tear (>2cm)",
    "Big Tear (>1 inch)",
    "Small Imperfections",
    "Big Imperfections",
    "Pressure Marks",
    "Slightly Dented",
    "Heavy Dented",
    "Damaged",
    "Box Only",
    "Contents Only"
  ]

  # Loads the user's portfolio holdings, summary entries and overview totals.
  def index
    if current_user
      @holdings = current_user.holdings.includes(:product).order(
        Arel.sql("COALESCE(purchase_date, DATE(holdings.created_at)) DESC"),
        created_at: :desc
      ).to_a

      Product.update_all_holding_totals(@holdings) if Product.respond_to?(:update_all_holding_totals)

      cost = @holdings.sum { |h| money_value(h.total_cost) }
      value = @holdings.sum { |h| money_value(h.total_value) }
      pl = value - cost
      roi = cost.zero? ? 0 : (pl / cost * 100)

      @eras = @holdings.map(&:era).compact.uniq.sort
      @types = @holdings.map(&:product_type).compact.uniq.sort
      @conditions = (@holdings.map(&:condition).compact.uniq + DEFAULT_CONDITIONS).uniq
      @summary_entries = summary_entries_for(current_user)
      @realised_pl_total = realised_pl_total_for(current_user)
    else
      @holdings = []
      @summary_entries = []
      cost = value = pl = roi = 0
      @eras = []
      @types = []
      @conditions = DEFAULT_CONDITIONS
      @realised_pl_total = 0.to_d
    end

    @totals = { cost: cost, value: value, pl: pl, roi: roi }
  end

  # Sends logged-out users back with the portfolio login flash message.
  def login_required
    redirect_to root_path, alert: "Please log in to view your Portfolio."
  end

  # Returns portfolio chart data as JSON for the portfolio metrics modal.
  def metrics
    unless current_user
      render json: { error: "not_signed_in", series: [], debug: { signed_in: false } }, status: :unauthorized
      return
    end

    response.headers["Cache-Control"] = "no-store"

    holdings = current_user.holdings.includes(:product).to_a
    Product.update_all_holding_totals(holdings) if Product.respond_to?(:update_all_holding_totals)

    holding_days = Hash.new { |h, k| h[k] = { cost: 0.to_d, value: 0.to_d } }

    holdings.each do |holding|
      date = holding.purchase_date || holding.created_at&.to_date
      next unless date

      holding_days[date][:cost] += money_value(holding.total_cost)
      holding_days[date][:value] += money_value(holding.total_value)
    end

    realised_days = realised_pl_by_date_for(current_user)

    all_dates = (holding_days.keys + realised_days.keys).compact.uniq.sort

    cum_cost = 0.to_d
    cum_value = 0.to_d
    cum_realised = 0.to_d

    series = all_dates.map do |date|
      day_holdings = holding_days[date]
      day_realised = realised_days[date] || 0.to_d

      cum_cost += day_holdings[:cost]
      cum_value += day_holdings[:value]
      cum_realised += money_value(day_realised)

      pl = cum_value - cum_cost
      roi = cum_cost.zero? ? 0.to_d : (pl / cum_cost * 100)

      {
        date: date.strftime("%Y-%m-%d"),
        cost: cum_cost.to_f,
        value: cum_value.to_f,
        total_cost: cum_cost.to_f,
        total_value: cum_value.to_f,
        pl: pl.to_f,
        roi: roi.to_f,
        realised_pl: cum_realised.to_f,
        realized_pl: cum_realised.to_f
      }
    end

    render json: {
      series: series,
      realised_pl_series: {
        labels: series.map { |point| point[:date] },
        values: series.map { |point| point[:realised_pl] }
      },
      debug: {
        signed_in: true,
        holdings_count: holdings.size,
        summary_entries_count: summary_entries_for(current_user).size,
        marketplace_sales_count: marketplace_sales_for(current_user).size,
        date_points: series.size,
        realised_pl_total: cum_realised.to_f
      }
    }
  end

  private

  # Converts a value into BigDecimal so money calculations stay safe.
  def money_value(value)
    BigDecimal(value.to_s)
  rescue
    BigDecimal("0")
  end

  # Finds all portfolio summary entries for a user.
  def summary_entries_for(user)
    return [] unless defined?(SummaryEntry)
    return [] unless user

    SummaryEntry.where(user_id: user.id).order(created_at: :desc).to_a
  rescue
    []
  end

  # Finds sold portfolio summary entries for a user.
  def sold_summary_entries_for(user)
    return [] unless defined?(SummaryEntry)
    return [] unless user

    SummaryEntry.where(user_id: user.id, action: [ "SOLD", "Sold", "sold" ]).to_a
  rescue
    []
  end

  # Finds marketplace sales where the user was the seller.
  def marketplace_sales_for(user)
    return [] unless defined?(MarketplacePurchase)
    return [] unless user

    MarketplacePurchase.where(seller_id: user.id).to_a
  rescue
    []
  end

  # Calculates the user's total realised profit/loss from sold items and marketplace sales.
  def realised_pl_total_for(user)
    realised_pl_by_date_for(user).values.sum { |value| money_value(value) }
  rescue
    BigDecimal("0")
  end

  # Groups realised profit/loss by date for portfolio metrics.
  def realised_pl_by_date_for(user)
    out = Hash.new(0.to_d)

    marketplace_sales_for(user).each do |purchase|
      date = purchase.created_at&.to_date || Date.current
      out[date] += money_value(purchase.realised_pl_cents) / 100
    end

    sold_summary_entries_for(user).each do |entry|
      date = entry.purchase_date || entry.created_at&.to_date || Date.current
      quantity = entry.quantity.to_i
      quantity = 1 if quantity <= 0

      cost_per_unit = money_value(entry.cost_per_unit)
      sell_price = money_value(entry.value)

      out[date] += (sell_price - cost_per_unit) * quantity
    end

    out
  rescue
    Hash.new(0.to_d)
  end
end
