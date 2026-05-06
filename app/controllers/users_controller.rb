class UsersController < ApplicationController
  # Shows another user's public account page by reusing the account view template
  def show
    @user = User.find_by(id: params[:id])
    return redirect_to(root_path, alert: "User not found.") unless @user

    # Forces the account page into public-profile mode instead of self-account mode
    @is_self = false
    @tab = "current"
    @watchlist_items = []

    # Loads only active marketplace listings for the selected user
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

    render "accounts/show"
  end
end
