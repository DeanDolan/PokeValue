class MfaController < ApplicationController
  include Authentication

  before_action :require_admin_for_mfa

  def new
    @user = mfa_user
    return redirect_to(login_path, alert: "Log in first.", status: :see_other) unless @user
    if @user.admin? && !@user.mfa_enabled?
      redirect_to mfa_setup_path, status: :see_other
      nil
    end
  end

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

  def setup
    @user = mfa_user
    return redirect_to(login_path, alert: "Log in first.", status: :see_other) unless @user
    @user.ensure_mfa_secret!
    @otpauth_uri = @user.mfa_provisioning_uri
    @secret = @user.mfa_secret
  end

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

  def require_admin_for_mfa
    u = mfa_user
    unless u&.admin?
      redirect_to portfolio_path, alert: "Not authorised.", status: :see_other
    end
  end

  def mfa_user
    if session[:pre_mfa_user_id].present?
      User.find_by(id: session[:pre_mfa_user_id])
    else
      current_user
    end
  end

  def safe_return_to(path)
    p = path.to_s
    return nil if p.blank?
    return nil unless p.start_with?("/")
    return nil if p.start_with?("//")
    p
  end
end
