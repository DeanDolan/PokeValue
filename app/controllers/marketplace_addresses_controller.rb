class MarketplaceAddressesController < ApplicationController
  helper_method :current_user

  def destroy
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    addr = MarketplaceAddress.find_by(id: params[:id], user_id: current_user.id)
    addr&.destroy

    redirect_back(fallback_location: marketplace_path, notice: "Address deleted.")
  rescue
    redirect_back(fallback_location: marketplace_path, alert: "Could not delete address.")
  end

  private

  def current_user
    return @current_user if defined?(@current_user)
    @current_user = User.find_by(id: session[:user_id])
  end
end
