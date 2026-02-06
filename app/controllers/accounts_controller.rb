# References:
# - Rails controllers and filters:
#   https://guides.rubyonrails.org/action_controller_overview.html
# - before_action and redirects:
#   https://guides.rubyonrails.org/action_controller_overview.html#filters

class AccountsController < ApplicationController
  before_action :ensure_logged_in

  def show
    @user = current_user
    @watchlist_items =
      if @user.respond_to?(:watchlists)
        @user.watchlists.order(created_at: :desc)
      elsif @user.respond_to?(:watchlist_items)
        @user.watchlist_items.order(created_at: :desc)
      else
        []
      end
  end

  private

  def ensure_logged_in
    unless current_user
      redirect_to root_path, alert: "Please log in to view your account."
    end
  end
end
