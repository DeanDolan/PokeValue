module Authentication
  extend ActiveSupport::Concern

  ADMIN_MFA_TTL = 30.minutes

  included do
    helper_method :current_user, :user_signed_in?, :admin_signed_in?, :admin_mfa_verified?
  end

  def current_user
    return @current_user if defined?(@current_user)
    @current_user = session[:user_id].present? ? User.find_by(id: session[:user_id]) : nil
  end

  def user_signed_in?
    current_user.present?
  end

  def admin_signed_in?
    current_user&.admin? == true
  end

  def admin_mfa_verified?
    return false unless admin_signed_in?
    ts = session[:admin_mfa_at].to_i
    return false if ts <= 0
    Time.at(ts) > ADMIN_MFA_TTL.ago
  end

  def require_login!
    return if user_signed_in?
    redirect_to root_path, alert: "You must be logged in.", status: :see_other
  end

  def require_admin!
    return if admin_signed_in?
    redirect_to root_path, alert: "Not authorised.", status: :see_other
  end

  def require_admin_mfa!
    require_admin!
    return if admin_mfa_verified?
    redirect_to mfa_path, alert: "Admin actions require MFA verification.", status: :see_other
  end
end
