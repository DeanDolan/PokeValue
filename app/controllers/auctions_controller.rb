class AuctionsController < ApplicationController
  helper_method :current_user

  def new
    # Only logged-in users can create auctions.
    redirect_to(root_path, alert: "Please log in.") unless current_user
  end

  def create
    # Stops guests from creating auctions.
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    # Reads and cleans the form fields submitted from the create auction page.
    description = params[:auction_description].to_s.strip
    condition = params[:condition].to_s.strip
    reserve_status = params[:reserve_status].to_s.strip
    duration_key = params[:auction_duration].to_s.strip
    reserve_price = params[:reserve_price].to_s.strip

    # Converts the selected duration key into a label and number of seconds.
    duration = auction_duration_options[duration_key]
    return redirect_to(new_auction_path, alert: "Choose an auction time length.") unless duration
    return redirect_to(new_auction_path, alert: "Choose reserve status.") unless %w[Reserve No\ Reserve].include?(reserve_status)
    return redirect_to(new_auction_path, alert: "Auction description is required.") if description.blank?
    return redirect_to(new_auction_path, alert: "Condition is required.") if condition.blank?

    # Reserve auctions must have a valid reserve price.
    reserve_cents = nil
    if reserve_status == "Reserve"
      begin
        reserve_cents = (BigDecimal(reserve_price) * 100).to_i
      rescue
        reserve_cents = 0
      end

      return redirect_to(new_auction_path, alert: "Reserve price must be greater than 0.") if reserve_cents <= 0
    end

    # Allows up to 4 auction images and only accepts JPG/PNG files.
    uploads = Array(params[:photos]).compact
    return redirect_to(new_auction_path, alert: "You can upload up to 4 images.") if uploads.length > 4

    uploads.each do |file|
      content_type = file.content_type.to_s
      unless content_type == "image/png" || content_type == "image/jpeg" || content_type == "image/jpg"
        return redirect_to(new_auction_path, alert: "Images must be .jpg or .png.")
      end
    end

    # Builds the auction record with calculated end time and running status.
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

    # Saves the auction first, then attaches uploaded images if present.
    if auction.save
      uploads.each { |file| auction.photos.attach(file) } if uploads.any?
      redirect_to(auction_listing_path(auction), notice: "Auction created.")
    else
      redirect_to(new_auction_path, alert: auction.errors.full_messages.to_sentence.presence || "Could not create auction.")
    end
  end

  def show
    # Loads the auction, seller, bids, bidders and saved addresses for display.
    @auction = Auction.includes(:seller, auction_bids: [ :bidder, :saved_address ]).find(params[:id])

    # Refreshes status so expired auctions move into ended/payment states.
    @auction.refresh_status_and_settle!

    # Gets seller review stats for the auction page.
    @seller_stats =
      if defined?(Review)
        avg = Review.where(seller_id: @auction.seller_id).average(:rating).to_f
        count = Review.where(seller_id: @auction.seller_id).count
        { avg: avg, count: count }
      else
        { avg: 0.0, count: 0 }
      end

    # Shows all reviews under the auction details.
    @reviews =
      if defined?(Review)
        Review.where(seller_id: @auction.seller_id).includes(:reviewer).order(created_at: :desc).to_a
      else
        []
      end

    # Allows the winner to review the auction seller only after the seller verifies payment.
    @can_give_review =
      if current_user && defined?(Review)
        @auction.status.to_s == "sold" &&
          @auction.winning_bidder_id.to_i == current_user.id.to_i &&
          @auction.seller_id.to_i != current_user.id.to_i &&
          !Review.where(seller_id: @auction.seller_id, reviewer_id: current_user.id).exists?
      else
        false
      end
  end

  def bid
    # Only logged-in users can bid.
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    @auction = Auction.find(params[:id])

    # Makes sure the auction status is up to date before allowing a bid.
    @auction.refresh_status_and_settle!

    return redirect_to(auction_listing_path(@auction), alert: "You cannot bid on your own auction.") if @auction.seller_id.to_i == current_user.id.to_i
    return redirect_to(auction_listing_path(@auction), alert: "This auction is no longer open for bids.") unless @auction.running?

    # Finds the user's latest bid so the same saved address can be reused.
    @existing_bid = @auction.auction_bids.where(bidder_id: current_user.id).order(created_at: :desc).first
    @selected_address = @existing_bid&.saved_address

    # Loads saved addresses for first-time bids on this auction.
    @saved_addresses =
      if defined?(SavedAddress)
        SavedAddress.where(user_id: current_user.id).order(created_at: :desc)
      else
        []
      end

    # Minimum bid is 1 cent higher than the current highest bid.
    @minimum_bid_eur = ((@auction.current_bid_cents_value.to_i + 1) / 100.0).round(2)
  end

  def create_bid
    # Stops guests from bidding.
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    bid = nil

    ActiveRecord::Base.transaction do
      # Locks the auction row so two bids cannot update against stale data at the same time.
      auction = Auction.lock.find(params[:id])
      auction.refresh_status_and_settle!

      return redirect_to(auction_listing_path(auction), alert: "You cannot bid on your own auction.") if auction.seller_id.to_i == current_user.id.to_i
      return redirect_to(auction_listing_path(auction), alert: "This auction is no longer open for bids.") unless auction.running?

      # Converts the euro bid amount into cents.
      bid_cents =
        begin
          (BigDecimal(params[:bid_amount].to_s.strip) * 100).to_i
        rescue
          0
        end

      # Reuses the bidder's previous saved address for this auction if they already bid before.
      existing_bid = auction.auction_bids.where(bidder_id: current_user.id).order(created_at: :desc).first

      saved_address_id =
        if existing_bid&.saved_address_id.present?
          existing_bid.saved_address_id
        elsif defined?(SavedAddress)
          SavedAddress.where(user_id: current_user.id, id: params[:saved_address_id]).pick(:id)
        else
          params[:saved_address_id].presence
        end

      bid = AuctionBid.new(
        auction_id: auction.id,
        bidder_id: current_user.id,
        amount_cents: bid_cents,
        saved_address_id: saved_address_id
      )

      if bid.save
        redirect_to(auction_listing_path(auction), notice: "Bid placed.")
      else
        # Rebuilds the bid form if validation fails.
        @auction = auction
        @auction_bid = bid
        @existing_bid = existing_bid
        @selected_address = existing_bid&.saved_address
        @saved_addresses = defined?(SavedAddress) ? SavedAddress.where(user_id: current_user.id).order(created_at: :desc) : []
        @minimum_bid_eur = ((auction.current_bid_cents_value.to_i + 1) / 100.0).round(2)
        raise ActiveRecord::Rollback
      end
    end

    return if performed?

    render :bid, status: :unprocessable_entity
  end

  def end_auction
    # Only the auction owner can end eligible auctions early.
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    auction = Auction.find(params[:id])
    return redirect_to(auction_listing_path(auction), alert: "Forbidden.") unless auction.can_end_early_by?(current_user)

    auction.end_early!
    redirect_to(auction_listing_path(auction), notice: "Auction ended.")
  end

  def destroy
    return redirect_to(root_path, alert: "Please log in.", status: :see_other) unless current_user

    auction = Auction.find(params[:id])
    return redirect_to(auction_path, alert: "Not authorized.", status: :see_other) unless auction_admin_user?

    auction.destroy!
    redirect_to(auction_path, notice: "Auction deleted.", status: :see_other)
  rescue
    redirect_to(auction_path, alert: "Could not delete auction.", status: :see_other)
  end

  def confirm_payment
    # The winner confirms that they have sent payment.
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
    # The auction host verifies the payment after checking Revolut.
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

  # Reads the logged-in user from the session.
  def current_user
    return @current_user if defined?(@current_user)
    @current_user = User.find_by(id: session[:user_id])
  end

  def auction_admin_user?
    user = current_user
    return false unless user

    return true if user.respond_to?(:admin?) && user.admin?
    return true if user.respond_to?(:admin) && !!user.admin

    false
  rescue
    false
  end

  # Controls the auction duration dropdown values.
  def auction_duration_options
    {
      "1_minute" => { label: "1 min", seconds: 1.minute.to_i },
      "5_minutes" => { label: "5 mins", seconds: 5.minutes.to_i },
      "10_minutes" => { label: "10 mins", seconds: 10.minutes.to_i },
      "30_minutes" => { label: "30 mins", seconds: 30.minutes.to_i },
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
