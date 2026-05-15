class AccountsController < ApplicationController
  before_action :ensure_logged_in

  # Shows only the logged-in user's own account page.
  def show
    @user = current_user
    @is_self = true

    # Keeps the marketplace tab locked to one of the supported account tabs.
    @tab = params[:tab].to_s.strip
    @tab = "current" if @tab.blank?
    @tab = "current" unless %w[current sold bought].include?(@tab)

    # Only the account owner can see their own watchlist.
    @watchlist_items =
      if @user.respond_to?(:watchlists)
        @user.watchlists.order(created_at: :desc)
      elsif @user.respond_to?(:watchlist_items)
        @user.watchlist_items.order(created_at: :desc)
      else
        []
      end

    # Loads active marketplace listings created by this account.
    @current_listings =
      if defined?(MarketplaceListing)
        scope =
          if MarketplaceListing.respond_to?(:active)
            MarketplaceListing.active
          else
            MarketplaceListing.where(status: "active")
          end
        scope.where(seller_id: @user.id).order(created_at: :desc)
      else
        []
      end
  end

  private

  # Prevents access to account pages when no user is logged in.
  def ensure_logged_in
    redirect_to root_path, alert: "Please log in to view your account." unless current_user
  end
end
