class AccountsController < ApplicationController
  before_action :ensure_logged_in

  # Shows the logged-in user's account, or another user's public account page if an ID is supplied.
  def show
    @user =
      if params[:id].present?
        User.find_by(id: params[:id])
      else
        current_user
      end

    return redirect_to(root_path, alert: "User not found.") unless @user

    # Used by the view to decide whether private account sections should be shown.
    @is_self = current_user && current_user.id == @user.id

    # Keeps the marketplace tab locked to one of the supported account tabs.
    @tab = params[:tab].to_s.strip
    @tab = "current" if @tab.blank?
    @tab = "current" unless %w[current sold bought].include?(@tab)

    # Only the account owner can see their own watchlist.
    @watchlist_items = []
    if @is_self
      @watchlist_items =
        if @user.respond_to?(:watchlists)
          @user.watchlists.order(created_at: :desc)
        elsif @user.respond_to?(:watchlist_items)
          @user.watchlist_items.order(created_at: :desc)
        else
          []
        end
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
