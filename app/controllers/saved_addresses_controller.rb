class SavedAddressesController < ApplicationController
  before_action :require_login

  def create
    attrs = normalized_saved_address_attributes
    address_id = attrs.delete(:id).presence

    if address_id.present?
      @saved_address = SavedAddress.where(user_id: current_user.id).find(address_id)
      @saved_address.assign_attributes(attrs)
      success_notice = "Address updated successfully."
    else
      @saved_address = SavedAddress.new(attrs)
      @saved_address.user = current_user
      success_notice = "Address added successfully."
    end

    if @saved_address.save
      redirect_back fallback_location: account_path, notice: success_notice
    else
      redirect_back fallback_location: account_path, alert: @saved_address.errors.full_messages.to_sentence
    end
  end

  def destroy
    @saved_address = SavedAddress.where(user_id: current_user.id).find(params[:id])
    @saved_address.destroy
    redirect_back fallback_location: account_path, notice: "Address removed."
  end

  private

  def saved_address_params
    params.require(:saved_address).permit(:id, :label, :line1, :line2, :city, :county, :postcode, :country_code)
  end

  def normalized_saved_address_attributes
    attrs = saved_address_params.to_h.symbolize_keys
    attrs.delete(:label) unless SavedAddress.column_names.include?("label")
    attrs
  end

  def require_login
    return if respond_to?(:current_user, true) && current_user.present?

    redirect_to login_path
  end
end
