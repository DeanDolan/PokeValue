class ReviewsController < ApplicationController
  helper_method :current_user

  def create
    return redirect_back(fallback_location: marketplace_path, alert: "Please log in.") unless current_user

    seller_id = submitted_param(:seller_id).to_i
    rating_raw = submitted_param(:rating).to_s
    comment = submitted_param(:comment).to_s

    return redirect_back(fallback_location: marketplace_path, alert: "Invalid seller.") if seller_id <= 0
    return redirect_back(fallback_location: marketplace_path, alert: "You can't review yourself.") if seller_id == current_user.id
    return redirect_back(fallback_location: user_path(seller_id), alert: "You can only review a seller after buying from them or winning one of their auctions.") unless has_relationship_with_seller?(seller_id)
    return redirect_back(fallback_location: user_path(seller_id), alert: "You have already reviewed this user.") if already_reviewed?(seller_id)

    rating_value =
      begin
        BigDecimal(rating_raw)
      rescue
        nil
      end

    return redirect_back(fallback_location: user_path(seller_id), alert: "Rating must be between 0 and 5.") if rating_value.nil?
    return redirect_back(fallback_location: user_path(seller_id), alert: "Rating must be between 0 and 5.") if rating_value < 0 || rating_value > 5

    Review.create!(
      seller_id: seller_id,
      reviewer_id: current_user.id,
      rating: rating_value.round(1),
      comment: comment
    )

    redirect_back(fallback_location: user_path(seller_id), notice: "Review submitted.")
  rescue
    redirect_back(fallback_location: marketplace_path, alert: "Could not submit review.")
  end

  private

  def submitted_param(key)
    if params[:review].respond_to?(:[])
      nested = params[:review][key] || params[:review][key.to_s]
      return nested if nested.present?
    end

    params[key] || params[key.to_s]
  end

  def has_relationship_with_seller?(seller_id)
    marketplace_purchase_exists?(seller_id) || auction_win_exists?(seller_id)
  end

  def marketplace_purchase_exists?(seller_id)
    if defined?(MarketplacePurchase)
      cols = MarketplacePurchase.column_names

      if cols.include?("buyer_id") && cols.include?("seller_id")
        scope = MarketplacePurchase.where(seller_id: seller_id, buyer_id: current_user.id)
        scope = scope.where(status: "sold") if cols.include?("status")
        return scope.exists?
      end

      if cols.include?("buyer_id") && defined?(MarketplaceListing) && (cols.include?("marketplace_listing_id") || cols.include?("listing_id"))
        ref_col = cols.include?("marketplace_listing_id") ? "marketplace_listing_id" : "listing_id"
        seller_listing_ids = MarketplaceListing.where(seller_id: seller_id).pluck(:id)
        scope = MarketplacePurchase.where(buyer_id: current_user.id, ref_col => seller_listing_ids)
        scope = scope.where(status: "sold") if cols.include?("status")
        return scope.exists?
      end
    end

    if defined?(MarketplaceListing)
      cols = MarketplaceListing.column_names
      if cols.include?("buyer_id") && cols.include?("seller_id")
        scope = MarketplaceListing.where(seller_id: seller_id, buyer_id: current_user.id)
        scope = scope.where(status: "sold") if cols.include?("status")
        return scope.exists?
      end
    end

    false
  rescue
    false
  end

  def auction_win_exists?(seller_id)
    return false unless defined?(Auction)

    cols = Auction.column_names
    return false unless cols.include?("seller_id") && cols.include?("winning_bidder_id")

    scope = Auction.where(seller_id: seller_id, winning_bidder_id: current_user.id)
    scope = scope.where(status: "sold") if cols.include?("status")
    scope.exists?
  rescue
    false
  end

  def already_reviewed?(seller_id)
    Review.where(seller_id: seller_id, reviewer_id: current_user.id).exists?
  rescue
    false
  end

  def current_user
    return @current_user if defined?(@current_user)
    @current_user = User.find_by(id: session[:user_id])
  end
end
