# References I leaned on while wiring this up:
# - Rails controllers, redirects, flash, and status codes:
#   https://guides.rubyonrails.org/action_controller_overview.html
# - has_secure_password / authenticate behaviour:
#   https://api.rubyonrails.org/classes/ActiveModel/SecurePassword/ClassMethods.html

class SessionsController < ApplicationController
  include Authentication  # keep auth helpers (current_user, user_signed_in?, etc) available here

  # Separate new action so I can render a login form if needed outside the modal
  def new; end

  def create
    # Normalise the username before lookup so leading/trailing spaces don't break login
    @user = User.find_by(username: params[:username].to_s.strip)

    # If the account is locked, short-circuit before even checking the password
    if @user&.locked?
      redirect_to portfolio_path, alert: "Account locked. Try again later.", status: :see_other
      return
    end

    # Authenticate against the password digest set by has_secure_password
    if @user&.authenticate(params[:password])
      # On successful login, reset any failed-attempt counters if that logic exists
      @user.reset_failed_logins! if @user.respond_to?(:reset_failed_logins!)

      # Store the user id in the session so the user stays logged in between requests
      session[:user_id] = @user.id

      # Always come back to the portfolio after a successful login
      redirect_to portfolio_path, notice: "Logged in successfully!", status: :see_other
    else
      # If auth fails, bump failed attempts if that method is present on the model
      @user&.register_failed_login! if @user.respond_to?(:register_failed_login!)

      # Send the user back to the portfolio with a generic error (no hint which field was wrong)
      redirect_to portfolio_path, alert: "Invalid username or password.", status: :see_other
    end
  end

  def destroy
    # Clear everything in the session so the user is fully logged out
    reset_session

    # Redirect to portfolio as the default landing screen after logout
    redirect_to portfolio_path, notice: "Logged out.", status: :see_other
  end
end
