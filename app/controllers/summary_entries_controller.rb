class SummaryEntriesController < ApplicationController
  # Deletes one portfolio summary row.
  def destroy
    unless current_user
      redirect_to portfolio_login_required_path, alert: "Please log in to view your Portfolio."
      return
    end

    entry = SummaryEntry.where(user_id: current_user.id).find(params[:id])
    entry.destroy!

    redirect_back fallback_location: portfolio_path, notice: "Summary entry removed."
  rescue ActiveRecord::RecordNotFound
    redirect_back fallback_location: portfolio_path, alert: "Summary entry not found."
  rescue
    redirect_back fallback_location: portfolio_path, alert: "Could not remove summary entry."
  end

  # Deletes one sold summary row.
  def destroy_sold
    unless current_user
      redirect_to portfolio_login_required_path, alert: "Please log in to view your Portfolio."
      return
    end

    if defined?(MarketplacePurchase)
      purchase = MarketplacePurchase.where(seller_id: current_user.id).find_by(id: params[:id])

      if purchase
        purchase.destroy!
        redirect_back fallback_location: portfolio_path, notice: "Sold summary entry removed."
        return
      end
    end

    if defined?(SummaryEntry)
      entry = SummaryEntry.where(user_id: current_user.id, action: [ "SOLD", "Sold", "sold" ]).find_by(id: params[:id])

      if entry
        entry.destroy!
        redirect_back fallback_location: portfolio_path, notice: "Sold summary entry removed."
        return
      end
    end

    redirect_back fallback_location: portfolio_path, alert: "Sold summary row not found."
  rescue
    redirect_back fallback_location: portfolio_path, alert: "Could not remove sold summary row."
  end
end
