class SummaryEntriesController < ApplicationController
  # Deletes an added-item row from the portfolio summary modal
  def destroy
    unless defined?(user_signed_in?) && user_signed_in? && current_user
      redirect_to login_path and return
    end

    entry = SummaryEntry.where(user_id: current_user.id).find(params[:id])
    entry.destroy

    redirect_back fallback_location: portfolio_path
  end

  # Deletes a sold-item row from the portfolio summary modal
  def destroy_sold
    unless defined?(user_signed_in?) && user_signed_in? && current_user
      redirect_to login_path and return
    end

    if defined?(MarketplacePurchase)
      purchase = MarketplacePurchase.where(seller_id: current_user.id).find_by(id: params[:id])

      if purchase
        purchase.destroy
        redirect_back fallback_location: portfolio_path
        return
      end
    end

    if defined?(SummaryEntry)
      entry = SummaryEntry.where(user_id: current_user.id, action: [ "SOLD", "Sold", "sold" ]).find_by(id: params[:id])

      if entry
        entry.destroy
        redirect_back fallback_location: portfolio_path
        return
      end
    end

    redirect_back fallback_location: portfolio_path, alert: "Sold summary row not found."
  end
end
