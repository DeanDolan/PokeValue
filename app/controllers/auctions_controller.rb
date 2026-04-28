class AuctionsController < ApplicationController
  helper_method :current_user

  def new
    redirect_to(root_path, alert: "Please log in.") unless current_user
  end

  def create
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    description = params[:auction_description].to_s.strip
    condition = params[:condition].to_s.strip
    reserve_status = params[:reserve_status].to_s.strip
    duration_key = params[:auction_duration].to_s.strip
    reserve_price = params[:reserve_price].to_s.strip

    duration = auction_duration_options[duration_key]
    return redirect_to(new_auction_path, alert: "Choose an auction time length.") unless duration
    return redirect_to(new_auction_path, alert: "Choose reserve status.") unless %w[Reserve No\ Reserve].include?(reserve_status)
    return redirect_to(new_auction_path, alert: "Auction description is required.") if description.blank?
    return redirect_to(new_auction_path, alert: "Condition is required.") if condition.blank?

    reserve_cents = nil
    if reserve_status == "Reserve"
      begin
        reserve_cents = (BigDecimal(reserve_price) * 100).to_i
      rescue
        reserve_cents = 0
      end

      return redirect_to(new_auction_path, alert: "Reserve price must be greater than 0.") if reserve_cents <= 0
    end

    uploads = Array(params[:photos]).compact
    return redirect_to(new_auction_path, alert: "You can upload up to 4 images.") if uploads.length > 4

    uploads.each do |file|
      content_type = file.content_type.to_s
      unless content_type == "image/png" || content_type == "image/jpeg" || content_type == "image/jpg"
        return redirect_to(new_auction_path, alert: "Images must be .jpg or .png.")
      end
    end

    auction = Auction.new(
      seller_id: current_user.id,
      auction_description: description,
      condition: condition,
      reserve_status: reserve_status,
      reserve_cents: reserve_cents,
      auction_length_label: duration[:label],
      auction_length_seconds: duration[:seconds],
      ends_at: Time.current + duration[:seconds].seconds,
      status: "running"
    )

    if auction.save
      uploads.each { |file| auction.photos.attach(file) } if uploads.any?
      redirect_to(auction_listing_path(auction), notice: "Auction created.")
    else
      redirect_to(new_auction_path, alert: auction.errors.full_messages.to_sentence.presence || "Could not create auction.")
    end
  end

  def show
    @auction = Auction.includes(:seller, auction_bids: [ :bidder, :saved_address ]).find(params[:id])
    @auction.refresh_status_and_settle!

    @seller_stats =
      if defined?(Review)
        avg = Review.where(seller_id: @auction.seller_id).average(:rating).to_f
        count = Review.where(seller_id: @auction.seller_id).count
        { avg: avg, count: count }
      else
        { avg: 0.0, count: 0 }
      end

    @recent_reviews =
      if defined?(Review)
        Review.where(seller_id: @auction.seller_id).order(created_at: :desc).limit(10)
      else
        []
      end
  end

  def bid
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    @auction = Auction.find(params[:id])
    @auction.refresh_status_and_settle!

    return redirect_to(auction_listing_path(@auction), alert: "You cannot bid on your own auction.") if @auction.seller_id.to_i == current_user.id.to_i
    return redirect_to(auction_listing_path(@auction), alert: "This auction is no longer open for bids.") unless @auction.running?

    @existing_bid = @auction.auction_bids.where(bidder_id: current_user.id).order(created_at: :desc).first
    @selected_address = @existing_bid&.saved_address

    @saved_addresses =
      if defined?(SavedAddress)
        SavedAddress.where(user_id: current_user.id).order(created_at: :desc)
      else
        []
      end

    @minimum_bid_eur = ((@auction.current_bid_cents_value.to_i + 1) / 100.0).round(2)
  end

  def create_bid
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    auction = Auction.lock.find(params[:id])
    auction.refresh_status_and_settle!

    return redirect_to(auction_listing_path(auction), alert: "You cannot bid on your own auction.") if auction.seller_id.to_i == current_user.id.to_i
    return redirect_to(auction_listing_path(auction), alert: "This auction is no longer open for bids.") unless auction.running?

    bid_cents =
      begin
        (BigDecimal(params[:bid_amount].to_s.strip) * 100).to_i
      rescue
        0
      end

    existing_bid = auction.auction_bids.where(bidder_id: current_user.id).order(created_at: :desc).first
    saved_address_id = existing_bid&.saved_address_id.presence || params[:saved_address_id].to_i

    bid = AuctionBid.new(
      auction_id: auction.id,
      bidder_id: current_user.id,
      amount_cents: bid_cents,
      saved_address_id: saved_address_id
    )

    if bid.save
      redirect_to(auction_listing_path(auction), notice: "Bid placed.")
    else
      @auction = auction
      @auction_bid = bid
      @existing_bid = existing_bid
      @selected_address = existing_bid&.saved_address
      @saved_addresses = defined?(SavedAddress) ? SavedAddress.where(user_id: current_user.id).order(created_at: :desc) : []
      @minimum_bid_eur = ((auction.current_bid_cents_value.to_i + 1) / 100.0).round(2)
      render :bid, status: :unprocessable_entity
    end
  end

  def end_auction
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    auction = Auction.find(params[:id])
    return redirect_to(auction_listing_path(auction), alert: "Forbidden.") unless auction.can_end_early_by?(current_user)

    auction.end_early!
    redirect_to(auction_listing_path(auction), notice: "Auction ended.")
  end

  def confirm_payment
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    auction = Auction.lock.find(params[:id])
    auction.refresh_status_and_settle!

    return redirect_to(auction_listing_path(auction), alert: "Only the auction winner can confirm payment.") unless auction.winning_bidder&.id.to_i == current_user.id.to_i

    if auction.confirm_payment_by_winner!(current_user)
      redirect_to(auction_listing_path(auction), notice: "Payment confirmation submitted. The host can now verify payment.")
    else
      redirect_to(auction_listing_path(auction), alert: "Payment could not be confirmed.")
    end
  end

  def verify_payment
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    auction = Auction.lock.find(params[:id])
    auction.refresh_status_and_settle!

    return redirect_to(auction_listing_path(auction), alert: "Only the auction host can verify payment.") unless auction.seller_id.to_i == current_user.id.to_i

    if auction.verify_payment_by_seller!(current_user)
      redirect_to(auction_path(auction_tab: "sold"), notice: "Payment verified. Auction moved to Sold Auctions.")
    else
      redirect_to(auction_listing_path(auction), alert: "Payment could not be verified.")
    end
  end

  private

  def current_user
    return @current_user if defined?(@current_user)
    @current_user = User.find_by(id: session[:user_id])
  end

  def auction_duration_options
    {
      "1_minute" => { label: "1 min", seconds: 1.minute.to_i },
      "1_hour" => { label: "1 hour", seconds: 1.hour.to_i },
      "3_hours" => { label: "3 hours", seconds: 3.hours.to_i },
      "6_hours" => { label: "6 hours", seconds: 6.hours.to_i },
      "12_hours" => { label: "12 hours", seconds: 12.hours.to_i },
      "1_day" => { label: "1 day", seconds: 1.day.to_i },
      "3_days" => { label: "3 days", seconds: 3.days.to_i },
      "1_week" => { label: "1 week", seconds: 1.week.to_i }
    }
  end
end
