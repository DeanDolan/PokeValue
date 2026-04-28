class UsersController < ApplicationController
  def show
    @user = User.find_by(id: params[:id])
    return redirect_to(root_path, alert: "User not found.") unless @user

    @is_self = false
    @tab = "current"
    @watchlist_items = []

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
