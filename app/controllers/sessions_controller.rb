class SessionsController < ApplicationController
  def new
    # Login is handled inside the shared login/register modal, so this page redirects back to the portfolio.
    flash.keep
    redirect_to portfolio_path, status: :see_other
  end

  def create
    # Reads the login fields from the form and removes extra spaces from the username.
    username = params[:username].to_s.strip
    password = params[:password].to_s

    # Stops empty login forms before checking the database.
    message = login_field_error(username, password)
    return redirect_to_portfolio(alert: message) if message

    # Finds the user by username without caring about uppercase or lowercase letters.
    user = User.find_by("lower(username) = ?", username.downcase)

    # Stops login if the account has been temporarily locked.
    return redirect_to_portfolio(alert: "Account locked. Try again later.") if user&.locked?

    # Starts the session if the password is correct, otherwise records a failed login attempt.
    if user&.authenticate(password)
      log_user_in(user)
    else
      user&.register_failed_login! if user.respond_to?(:register_failed_login?)
      redirect_to_portfolio(alert: "Invalid username or password.")
    end
  end

  def destroy
    # Clears the session so the user is fully logged out.
    reset_session
    redirect_to portfolio_path, notice: "Logged out.", status: :see_other
  end

  private

  def login_field_error(username, password)
    # Keeps the same user-friendly validation messages as before.
    return "Username and password fields cannot be empty. Please complete both fields before logging in." if username.blank? && password.blank?
    return "Username field cannot be empty." if username.blank?
    return "Password field cannot be empty." if password.blank?

    nil
  end

  def log_user_in(user)
    # Clears failed login tracking after a successful password check.
    user.reset_failed_logins! if user.respond_to?(:reset_failed_logins!)

    # Saves the user ID before reset_session because reset_session clears all old session data.
    uid = user.id

    # Resets the session after login to reduce session-fixation risk.
    reset_session

    # Admin users must complete MFA before the full login session is created.
    if user.admin?
      session[:pre_mfa_user_id] = uid
      session[:post_auth_redirect] = portfolio_path

      redirect_to(user.mfa_enabled? ? mfa_path : mfa_setup_path, status: :see_other)
    else
      session[:user_id] = uid

      redirect_to portfolio_path,
                  notice: "Logged in successfully!",
                  status: :see_other
    end
  end

  def redirect_to_portfolio(options = {})
    # Sends the browser back to the portfolio after login errors or normal redirects.
    redirect_to portfolio_path, options.merge(status: :see_other)
  end
end
