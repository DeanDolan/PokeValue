# References:
# - Rails controllers and filters:
#   https://guides.rubyonrails.org/action_controller_overview.html
# - before_action and redirects:
#   https://guides.rubyonrails.org/action_controller_overview.html#filters

class AccountsController < ApplicationController
  # Make sure only logged-in users can hit anything in this controller
  before_action :ensure_logged_in

  def show
    # Just expose the current user to the view for the account page
    @user = current_user
  end

  private

  # Basic guard so this page is never reachable when logged out
  def ensure_logged_in
    unless current_user
      redirect_to root_path, alert: "Please log in to view your account."
    end
  end
end
