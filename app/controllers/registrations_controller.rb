class RegistrationsController < ApplicationController
  def new
    # Builds an empty user object for the full registration page.
    @user = User.new
  end

  def create
    # Reads and cleans the registration fields from the form.
    username = params[:username].to_s.strip
    revolut_tag = params[:revolut_tag].to_s.strip
    password = params[:password].to_s
    password_confirmation = params[:password_confirmation].to_s

    # Stops invalid registration details before trying to create the account.
    message = registration_error(username, revolut_tag, password, password_confirmation)
    return render_invalid_registration(message) if message

    # Creates the user with the same fields used by the original form.
    @user = User.new(
      username: username,
      country_code: params[:country_code],
      revolut_tag: revolut_tag,
      password: password,
      password_confirmation: password_confirmation
    )

    if @user.save
      # Starts a fresh session for the new account.
      uid = @user.id
      reset_session
      session[:user_id] = uid

      redirect_to portfolio_path,
                  notice: "Welcome, #{@user.username}! Your account has been created.",
                  status: :see_other
    else
      flash.now[:alert] = @user.errors.full_messages.first || "Could not create account."
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_error(username, revolut_tag, password, password_confirmation)
    # Keeps the same registration checks and messages, but keeps the controller smaller.
    return "Username is required." if username.blank?
    return "Username must be 5-15 characters long." if username.length < User::USERNAME_MIN || username.length > User::USERNAME_MAX
    return "Username can only contain letters, numbers, dots, underscores or dashes." unless username.match?(/\A[A-Za-z0-9._-]+\z/)
    return "Username must not be an email address." if username.include?("@")
    return "Country is required." if params[:country_code].blank?
    return "Revolut Tag is required." if revolut_tag.blank?
    return "Revolut Tag must contain 3-30 letters, numbers, dots, underscores or dashes. Example: @dola123." unless revolut_tag.match?(/\A@?[A-Za-z0-9._-]{3,30}\z/)
    return "Password is required." if password.blank?
    return "Password confirmation is required." if password_confirmation.blank?
    return "Passwords do not match." if password != password_confirmation
    return "Password must be 12-20 characters long." if password.length < User::PASSWORD_MIN || password.length > User::PASSWORD_MAX
    return "Password must include at least one uppercase letter." unless password.match?(/[A-Z]/)
    return "Password must include at least one lowercase letter." unless password.match?(/[a-z]/)
    return "Password must include at least one number." unless password.match?(/\d/)
    return "Password must include at least one symbol." unless password.match?(/[^A-Za-z0-9]/)
    return "Password cannot contain your username." if password.downcase.include?(username.downcase)
    return "You must confirm that you understand the account safety notice before registering." unless accepted?(:account_safety_accepted)
    return "You must confirm that you understand your Revolut tag may be shown during payment-related actions." unless accepted?(:revolut_tag_visibility_accepted)
    return "You must agree to the account safety notice, payment visibility notice, security notice and platform terms before registering." unless accepted?(:platform_terms_accepted)

    nil
  end

  def accepted?(key)
    # Checkbox values submit as "1" when the user ticks them.
    params[key].to_s == "1"
  end

  def render_invalid_registration(message)
    # Re-renders the registration page with the same alert behaviour as before.
    @user = User.new
    flash.now[:alert] = message
    render :new, status: :unprocessable_entity
  end
end
