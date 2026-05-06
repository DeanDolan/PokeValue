class WatchlistsController < ApplicationController
  include Authentication

  before_action :require_login_for_watchlist

  # Adds a product SKU to the current user's watchlist
  def create
    sku = normalize_sku(params[:sku])
    return_to = safe_return_to(params[:return_to])

    current_user.watchlists.find_or_create_by!(product_sku: sku)

    redirect_to(return_to || portfolio_path, notice: "Added to watchlist.", status: :see_other)
  end

  # Removes a product SKU from the current user's watchlist
  def destroy
    sku = normalize_sku(params[:sku])
    return_to = safe_return_to(params[:return_to])

    current_user.watchlists.where(product_sku: sku).delete_all

    redirect_to(return_to || portfolio_path, notice: "Removed from watchlist.", status: :see_other)
  end

  private

  # Blocks watchlist actions unless the user is logged in
  def require_login_for_watchlist
    unless current_user
      redirect_to login_path, alert: "Please log in.", status: :see_other
    end
  end

  # Allows only the SKU format used by product pages, including variant route parts
  def normalize_sku(raw)
    s = raw.to_s
    raise ActiveRecord::RecordNotFound unless s.match?(/\A[a-zA-Z0-9\-_]+:[a-zA-Z0-9\-_]+(?:--[a-zA-Z0-9\-_]+)*\z/)
    raise ActiveRecord::RecordNotFound if s.length > 255
    s
  end

  # Allows redirects only to local app paths, not outside websites
  def safe_return_to(path)
    p = path.to_s
    return nil if p.blank?
    return nil unless p.start_with?("/")
    return nil if p.start_with?("//")
    p
  end
end
