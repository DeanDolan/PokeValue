class MfaController < ApplicationController
  # Gives this controller access to current_user and login session helpers
  include Authentication

  # Only admin users are allowed to access the MFA flow
  before_action :require_admin_for_mfa

  # Shows the MFA code form after the admin has entered their password
  def new
    @user = mfa_user
    return redirect_to(login_path, alert: "Log in first.", status: :see_other) unless @user
    if @user.admin? && !@user.mfa_enabled?
      redirect_to mfa_setup_path, status: :see_other
      nil
    end
  end

  # Verifies the submitted authenticator code and completes the admin login
  def create
    @user = mfa_user
    return redirect_to(login_path, alert: "Log in first.", status: :see_other) unless @user

    if @user.mfa_locked?
      redirect_to mfa_path, alert: "MFA temporarily locked. Try again later.", status: :see_other
      return
    end

    code = params[:code].to_s.gsub(/\s+/, "")

    if @user.verify_mfa_code!(code)
      session[:admin_mfa_at] = Time.current.to_i

      if session[:pre_mfa_user_id].present?
        uid = @user.id
        return_to = safe_return_to(session[:post_auth_redirect]) || portfolio_path
        reset_session
        session[:user_id] = uid
        session[:admin_mfa_at] = Time.current.to_i
        redirect_to return_to, notice: "Admin verified.", status: :see_other
      else
        redirect_back fallback_location: portfolio_path, notice: "MFA verified.", status: :see_other
      end
    else
      redirect_to mfa_path, alert: "Invalid code.", status: :see_other
    end
  end

  # Creates the MFA secret and shows the setup QR-code details
  def setup
    @user = mfa_user
    return redirect_to(login_path, alert: "Log in first.", status: :see_other) unless @user
    @user.ensure_mfa_secret!
    @otpauth_uri = @user.mfa_provisioning_uri
    @secret = @user.mfa_secret
  end

  # Enables MFA after the first valid authenticator code is entered
  def enable
    @user = mfa_user
    return redirect_to(login_path, alert: "Log in first.", status: :see_other) unless @user
    code = params[:code].to_s.gsub(/\s+/, "")
    codes = @user.enable_mfa!(code)

    if codes
      @otpauth_uri = @user.mfa_provisioning_uri
      @secret = @user.mfa_secret
      @recovery_codes = codes
      render :setup, status: :ok
    else
      redirect_to mfa_setup_path, alert: "Invalid code.", status: :see_other
    end
  end

  private

  # Stops non-admin users from entering the admin MFA area
  def require_admin_for_mfa
    u = mfa_user
    unless u&.admin?
      redirect_to portfolio_path, alert: "Not authorised.", status: :see_other
    end
  end

  # Finds either the admin waiting for MFA or the already logged-in user
  def mfa_user
    if session[:pre_mfa_user_id].present?
      User.find_by(id: session[:pre_mfa_user_id])
    else
      current_user
    end
  end

  # Prevents unsafe redirect paths after MFA verification
  def safe_return_to(path)
    p = path.to_s
    return nil if p.blank?
    return nil unless p.start_with?("/")
    return nil if p.start_with?("//")
    p
  end
end
