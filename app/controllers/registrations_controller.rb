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
    return redirect_invalid_registration(message) if message

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
      redirect_invalid_registration(@user.errors.full_messages.first || "Could not create account.")
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

    nil
  end

  def redirect_invalid_registration(message)
    redirect_back fallback_location: root_path, alert: message, status: :see_other
  end
end
