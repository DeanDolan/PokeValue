module Authentication
  extend ActiveSupport::Concern

  # Admin MFA stays valid for 30 minutes after a successful MFA check.
  ADMIN_MFA_TTL = 30.minutes

  included do
    # Makes these methods available inside views as well as controllers.
    helper_method :current_user, :user_signed_in?, :admin_signed_in?, :admin_mfa_verified?
  end

  def current_user
    # Reuses @current_user if it has already been loaded during this request.
    return @current_user if defined?(@current_user)

    # If session[:user_id] exists, find that user in the database.
    # If there is no session user ID, current_user is nil.
    @current_user = session[:user_id].present? ? User.find_by(id: session[:user_id]) : nil
  end

  def user_signed_in?
    # Returns true when current_user exists.
    current_user.present?
  end

  def admin_signed_in?
    # Returns true only when the logged-in user is an admin.
    current_user&.admin? == true
  end

  def admin_mfa_verified?
    # MFA only matters for logged-in admin users.
    return false unless admin_signed_in?

    # Reads the time when MFA was completed from the session.
    ts = session[:admin_mfa_at].to_i

    # If no MFA timestamp exists, MFA has not been verified.
    return false if ts <= 0

    # MFA is valid only if it happened within the last 30 minutes.
    Time.at(ts) > ADMIN_MFA_TTL.ago
  end

  def require_login!
    # Allows the request to continue if a user is logged in.
    return if user_signed_in?

    # Sends logged-out users back to the home page.
    redirect_to root_path, alert: "You must be logged in.", status: :see_other
  end

  def require_admin!
    # Allows the request to continue if the logged-in user is an admin.
    return if admin_signed_in?

    # Sends non-admin users back to the home page.
    redirect_to root_path, alert: "Not authorised.", status: :see_other
  end

  def require_admin_mfa!
    # First checks that the user is an admin.
    require_admin!

    # Allows the request to continue if admin MFA is still valid.
    return if admin_mfa_verified?

    # Sends the admin to MFA verification if MFA is missing or expired.
    redirect_to mfa_path, alert: "Admin actions require MFA verification.", status: :see_other
  end
end
