class SessionsController < ApplicationController
  # Gives this controller access to current_user and other auth helper methods
  include Authentication

  def new; end

  # Checks username and password, then starts either a normal or admin MFA session
  def create
    username = params[:username].to_s.strip
    password = params[:password].to_s

    if username.blank? && password.blank?
      redirect_to portfolio_path,
                  alert: "Username and password fields cannot be empty. Please complete both fields before logging in.",
                  status: :see_other
      return
    end

    if username.blank?
      redirect_to portfolio_path,
                  alert: "Username field cannot be empty.",
                  status: :see_other
      return
    end

    if password.blank?
      redirect_to portfolio_path,
                  alert: "Password field cannot be empty.",
                  status: :see_other
      return
    end

    u = User.find_by("lower(username) = ?", username.downcase)

    if u&.locked?
      redirect_to portfolio_path,
                  alert: "Account locked. Try again later.",
                  status: :see_other
      return
    end

    if u&.authenticate(password)
      u.reset_failed_logins! if u.respond_to?(:reset_failed_logins!)

      if u.admin?
        uid = u.id
        admin_mfa_path = u.mfa_enabled? ? mfa_path : mfa_setup_path

        reset_session
        session[:pre_mfa_user_id] = uid
        session[:post_auth_redirect] = portfolio_path

        redirect_to admin_mfa_path, status: :see_other
        return
      end

      uid = u.id

      reset_session
      session[:user_id] = uid

      redirect_to portfolio_path,
                  notice: "Logged in successfully!",
                  status: :see_other
    else
      u&.register_failed_login! if u.respond_to?(:register_failed_login!)

      redirect_to portfolio_path,
                  alert: "Invalid username or password.",
                  status: :see_other
    end
  end

  # Clears all session data and logs the user out
  def destroy
    reset_session
    redirect_to portfolio_path, notice: "Logged out.", status: :see_other
  end
end
