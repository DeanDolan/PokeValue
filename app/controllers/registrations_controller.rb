# References I leaned on when wiring this up:
# - Rails controllers, params, redirects and rendering:
#   https://guides.rubyonrails.org/action_controller_overview.html
# - Rails form helpers and strong parameters patterns:
#   https://guides.rubyonrails.org/form_helpers.html
# - Basic Ruby string handling (strip, length):
#   https://ruby-doc.org/core/String.html

class RegistrationsController < ApplicationController
  def new
    # Build a blank user so the registration form has an object to bind to
    @user = User.new
  end

  def create
    # Normalise username input by trimming spaces before validating/saving
    username = params[:username].to_s.strip

    # Enforce 5–15 chars on the server as well so I'm not relying only on HTML attributes
    if username.length < 5 || username.length > 15
      redirect_to register_path,
                  alert: "Username must be between 5 and 15 characters long. "\
                         "You entered #{username.length} characters.",
                  status: :see_other
      return
    end

    # Build the user from the incoming params
    @user = User.new(
      username: username,
      country_code: params[:country_code],
      password: params[:password],
      password_confirmation: params[:password_confirmation]
    )

    if @user.save
      # As soon as registration succeeds, log the user in by setting the session
      session[:user_id] = @user.id

      # Redirect them straight to the portfolio as the post-sign-up landing page
      redirect_to portfolio_path,
                  notice: "Welcome, #{@user.username}! Your account has been created.",
                  status: :see_other
    else
      # If validations fail, keep the form on the same page and show the first error
      flash.now[:alert] = @user.errors.full_messages.first || "Could not create account."
      render :new, status: :unprocessable_entity
    end
  end
end
