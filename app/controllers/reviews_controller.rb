class ReviewsController < ApplicationController
  helper_method :current_user

  def create
    return redirect_back(fallback_location: marketplace_path, alert: "Please log in.") unless current_user

    seller_id = review_param(:seller_id).to_i
    rating_raw = review_param(:rating).to_s.strip
    comment = review_param(:comment).to_s.strip

    return redirect_back(fallback_location: marketplace_path, alert: "Invalid seller.") if seller_id <= 0
    return redirect_back(fallback_location: user_path(seller_id), alert: "You can't review yourself.") if seller_id == current_user.id
    return redirect_back(fallback_location: user_path(seller_id), alert: "You can only review a seller after you have completed a marketplace purchase, won an auction, or won a raffle from them.") unless confirmed_paid_relationship_with_seller?(seller_id)
    return redirect_back(fallback_location: user_path(seller_id), alert: "You have already reviewed this user.") if already_reviewed?(seller_id)
    return redirect_back(fallback_location: user_path(seller_id), alert: "Rating must be between 0 and 5 with one decimal place.") unless valid_rating_format?(rating_raw)

    Review.create!(
      seller_id: seller_id,
      reviewer_id: current_user.id,
      rating: BigDecimal(rating_raw),
      comment: comment
    )

    redirect_back(fallback_location: user_path(seller_id), notice: "Review submitted.")
  rescue
    redirect_back(fallback_location: marketplace_path, alert: "Could not submit review.")
  end

  private

  def review_param(key)
    if params[:review].respond_to?(:[])
      value = params[:review][key] || params[:review][key.to_s]
      return value if value.present?
    end

    params[key] || params[key.to_s]
  end

  def valid_rating_format?(raw)
    return false unless raw.match?(/\A(?:[0-4](?:\.\d)?|5(?:\.0)?)\z/)

    value = BigDecimal(raw)
    value >= 0 && value <= 5
  rescue
    false
  end

  def confirmed_paid_relationship_with_seller?(seller_id)
    marketplace_confirmed_paid_offer_exists?(seller_id) || auction_confirmed_paid_win_exists?(seller_id) || raffle_completed_win_exists?(seller_id)
  end

  def marketplace_confirmed_paid_offer_exists?(seller_id)
    return false unless defined?(MarketplaceOffer)

    MarketplaceOffer.where(
      seller_id: seller_id,
      buyer_id: current_user.id,
      status: "confirmed_paid"
    ).exists?
  rescue
    false
  end

  def auction_confirmed_paid_win_exists?(seller_id)
    return false unless defined?(Auction)

    cols = Auction.column_names
    return false unless cols.include?("seller_id") && cols.include?("winning_bidder_id")

    scope = Auction.where(seller_id: seller_id, winning_bidder_id: current_user.id)
    scope = scope.where(status: "sold") if cols.include?("status")
    scope.exists?
  rescue
    false
  end

  def raffle_completed_win_exists?(seller_id)
    return false unless defined?(Raffle)

    cols = Raffle.column_names
    return false unless cols.include?("host_id") && cols.include?("winner_user_id")

    scope = Raffle.where(host_id: seller_id, winner_user_id: current_user.id)
    scope = scope.where(status: "completed") if cols.include?("status")
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
