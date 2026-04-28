class SummaryEntriesController < ApplicationController
  def destroy
    unless defined?(user_signed_in?) && user_signed_in? && current_user
      redirect_to login_path and return
    end

    entry = SummaryEntry.where(user_id: current_user.id).find(params[:id])
    entry.destroy

    redirect_back fallback_location: portfolio_path
  end

  def destroy_sold
    unless defined?(user_signed_in?) && user_signed_in? && current_user
      redirect_to login_path and return
    end

    unless defined?(MarketplacePurchase)
      redirect_back fallback_location: portfolio_path, alert: "Sold summary row not found." and return
    end

    purchase = MarketplacePurchase.where(seller_id: current_user.id).find(params[:id])
    purchase.destroy

    redirect_back fallback_location: portfolio_path
  end
end
