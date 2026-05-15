class SessionsController < ApplicationController
  def create
    # Gets the submitted username and removes extra spaces.
    username = params[:username].to_s.strip

    # Gets the submitted password exactly as typed.
    password = params[:password].to_s

    # Checks if username or password fields are empty before searching the database.
    message = login_field_error(username, password)

    # Sends the user back with an error message if required fields are missing.
    return redirect_to_portfolio(alert: message) if message

    # Finds the user by username without caring about uppercase or lowercase letters.
    user = User.find_by("lower(username) = ?", username.downcase)

    # Blocks login if the account is temporarily locked after too many failed attempts.
    return redirect_to_portfolio(alert: "Account locked. Try again later.") if user&.locked?

    # Logs the user in if the password is correct.
    if user&.authenticate(password)
      log_user_in(user)
    else
      # Records one failed login attempt if the username exists.
      user&.register_failed_login! if user.respond_to?(:register_failed_login!)

      # Sends the user back with a general invalid login message.
      redirect_to_portfolio(alert: "Invalid username or password.")
    end
  end

  def destroy
    # Clears all session data, which logs the user out.
    reset_session

    # Sends the user back to the portfolio after logout.
    redirect_to portfolio_path, notice: "Logged out.", status: :see_other
  end

  private

  def login_field_error(username, password)
    # Shows a specific message if both fields are empty.
    return "Username and password fields cannot be empty. Please complete both fields before logging in." if username.blank? && password.blank?

    # Shows a specific message if only the username is empty.
    return "Username field cannot be empty." if username.blank?

    # Shows a specific message if only the password is empty.
    return "Password field cannot be empty." if password.blank?

    # Returns nil when both fields are filled in.
    nil
  end

  def log_user_in(user)
    # Clears failed login attempts after a successful password check.
    user.reset_failed_logins! if user.respond_to?(:reset_failed_logins!)

    # Resets the session to help prevent session fixation attacks.
    reset_session

    # Admin users must complete MFA before being fully logged in.
    if user.admin?
      # Temporarily stores the admin user ID until MFA is completed.
      session[:pre_mfa_user_id] = user.id

      # Stores where the admin should be redirected after MFA.
      session[:post_auth_redirect] = portfolio_path

      # Sends admin users to MFA verification or MFA setup.
      redirect_to(user.mfa_enabled? ? mfa_path : mfa_setup_path, status: :see_other)
    else
      # Stores the normal logged-in user's ID in the session.
      session[:user_id] = user.id

      # Sends the user to the portfolio with a success message.
      redirect_to portfolio_path,
                  notice: "Logged in successfully!",
                  status: :see_other
    end
  end

  def redirect_to_portfolio(options = {})
    # Reusable helper for sending users back to the portfolio with flash messages.
    redirect_to portfolio_path, options.merge(status: :see_other)
  end
end
