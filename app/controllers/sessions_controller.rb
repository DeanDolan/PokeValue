class SessionsController < ApplicationController
  include Authentication

  def new; end

  def create
    u = User.find_by("lower(username) = ?", params[:username].to_s.strip.downcase)

    if u&.locked?
      redirect_to portfolio_path, alert: "Account locked. Try again later.", status: :see_other
      return
    end

    if u&.authenticate(params[:password])
      u.reset_failed_logins! if u.respond_to?(:reset_failed_logins!)

      if u.admin?
        uid = u.id
        reset_session
        session[:pre_mfa_user_id] = uid
        session[:post_auth_redirect] = portfolio_path
        redirect_to(u.mfa_enabled? ? mfa_path : mfa_setup_path, status: :see_other)
        return
      end

      uid = u.id
      reset_session
      session[:user_id] = uid
      redirect_to portfolio_path, notice: "Logged in successfully!", status: :see_other
    else
      u&.register_failed_login! if u.respond_to?(:register_failed_login!)
      redirect_to portfolio_path, alert: "Invalid username or password.", status: :see_other
    end
  end

  def destroy
    reset_session
    redirect_to portfolio_path, notice: "Logged out.", status: :see_other
  end
end
