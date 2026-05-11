class AuctionsController < ApplicationController
  helper_method :current_user

  # Opens the create auction form.
  def new
    redirect_to(root_path, alert: "Please log in.") unless current_user
  end

  # Creates an auction with description, condition, reserve details and duration.
  def create
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    duration = Auction.duration_for(params[:auction_duration])
    reserve_status = params[:reserve_status].to_s.strip
    description = params[:auction_description].to_s.strip
    condition = params[:condition].to_s.strip

    return redirect_to(new_auction_path, alert: "Choose an auction time length.") unless duration
    return redirect_to(new_auction_path, alert: "Choose reserve status.") unless Auction::RESERVE_STATUSES.include?(reserve_status)
    return redirect_to(new_auction_path, alert: "Auction description is required.") if description.blank?
    return redirect_to(new_auction_path, alert: "Condition is required.") if condition.blank?

    reserve_cents = reserve_status == "Reserve" ? money_to_cents(params[:reserve_price]) : nil
    return redirect_to(new_auction_path, alert: "Reserve price must be greater than 0.") if reserve_status == "Reserve" && reserve_cents.to_i <= 0

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
      redirect_to(auction_listing_path(auction), notice: "Auction created.")
    else
      redirect_to(new_auction_path, alert: auction.errors.full_messages.to_sentence.presence || "Could not create auction.")
    end
  end

  # Shows one auction, seller stats, reviews and payment state.
  def show
    @auction = Auction.includes(:seller, auction_bids: [ :bidder, :saved_address ]).find(params[:id])
    @auction.refresh_status_and_settle!

    @seller_stats = seller_stats_for(@auction.seller_id)
    @reviews = reviews_for(@auction.seller_id)
    @can_give_review = can_give_review?(@auction)
  end

  # Opens the bid form.
  def bid
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    @auction = Auction.find(params[:id])
    @auction.refresh_status_and_settle!

    return redirect_to(auction_listing_path(@auction), alert: "You cannot bid on your own auction.") if @auction.seller_id.to_i == current_user.id.to_i
    return redirect_to(auction_listing_path(@auction), alert: "This auction is no longer open for bids.") unless @auction.running?

    prepare_bid_form(@auction)
  end

  # Creates a bid and reuses the bidder's first saved address on later bids.
  def create_bid
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    saved = false

    ActiveRecord::Base.transaction do
      @auction = Auction.lock.find(params[:id])
      @auction.refresh_status_and_settle!

      return redirect_to(auction_listing_path(@auction), alert: "You cannot bid on your own auction.") if @auction.seller_id.to_i == current_user.id.to_i
      return redirect_to(auction_listing_path(@auction), alert: "This auction is no longer open for bids.") unless @auction.running?

      existing_bid = latest_bid_for(@auction)
      @auction_bid = @auction.auction_bids.build(
        bidder_id: current_user.id,
        amount_cents: money_to_cents(params[:bid_amount]),
        saved_address_id: saved_address_id_for_bid(existing_bid)
      )

      saved = @auction_bid.save
    end

    if saved
      redirect_to(auction_listing_path(@auction), notice: "Bid placed.")
    else
      prepare_bid_form(@auction)
      render :bid, status: :unprocessable_entity
    end
  end

  # Lets the host end an auction early only when the model allows it.
  def end_auction
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    auction = Auction.find(params[:id])
    return redirect_to(auction_listing_path(auction), alert: "Forbidden.") unless auction.can_end_early_by?(current_user)

    auction.end_early_by!(current_user)
    redirect_to(auction_listing_path(auction), notice: "Auction ended.")
  end

  # Lets an admin delete an auction.
  def destroy
    return redirect_to(root_path, alert: "Please log in.", status: :see_other) unless current_user
    return redirect_to(auction_path, alert: "Not authorized.", status: :see_other) unless auction_admin_user?

    Auction.find(params[:id]).destroy!
    redirect_to(auction_path, notice: "Auction deleted.", status: :see_other)
  rescue
    redirect_to(auction_path, alert: "Could not delete auction.", status: :see_other)
  end

  # Winner confirms that they have sent Revolut payment.
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

  # Host verifies payment and moves the auction to sold.
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

  # Finds the logged-in user from the session.
  def current_user
    return @current_user if defined?(@current_user)

    @current_user = User.find_by(id: session[:user_id])
  end

  # Checks whether the logged-in user is an admin.
  def auction_admin_user?
    user = current_user
    return false unless user
    return true if user.respond_to?(:admin?) && user.admin?
    return true if user.respond_to?(:admin) && !!user.admin

    false
  rescue
    false
  end

  # Converts euro form values into cents.
  def money_to_cents(value)
    (BigDecimal(value.to_s.strip.tr(",", ".")) * 100).to_i
  rescue
    0
  end

  # Gets seller review average and count.
  def seller_stats_for(seller_id)
    return { avg: 0.0, count: 0 } unless defined?(Review)

    {
      avg: Review.where(seller_id: seller_id).average(:rating).to_f,
      count: Review.where(seller_id: seller_id).count
    }
  rescue
    { avg: 0.0, count: 0 }
  end

  # Loads seller reviews for display on the auction show page.
  def reviews_for(seller_id)
    return [] unless defined?(Review)

    Review.where(seller_id: seller_id).includes(:reviewer).order(created_at: :desc).to_a
  rescue
    []
  end

  # Allows the winning bidder to review the seller once.
  def can_give_review?(auction)
    return false unless current_user && defined?(Review)
    return false unless auction.status.to_s == "sold"
    return false unless auction.winning_bidder_id.to_i == current_user.id.to_i
    return false if auction.seller_id.to_i == current_user.id.to_i

    !Review.where(seller_id: auction.seller_id, reviewer_id: current_user.id).exists?
  rescue
    false
  end

  # Gets the current user's latest bid on this auction.
  def latest_bid_for(auction)
    auction.auction_bids.where(bidder_id: current_user.id).order(created_at: :desc).first
  end

  # Gets the saved address for a bid.
  def saved_address_id_for_bid(existing_bid)
    return existing_bid.saved_address_id if existing_bid&.saved_address_id.present?

    return nil unless defined?(SavedAddress)

    SavedAddress.where(user_id: current_user.id, id: params[:saved_address_id]).pick(:id)
  end

  # Prepares variables needed by the bid page.
  def prepare_bid_form(auction)
    @existing_bid = latest_bid_for(auction)
    @selected_address = @existing_bid&.saved_address
    @saved_addresses = saved_addresses_for(current_user)
    @minimum_bid_eur = ((auction.current_bid_cents_value.to_i + 1) / 100.0).round(2)
  end

  # Loads saved addresses for the current user.
  def saved_addresses_for(user)
    return [] unless user && defined?(SavedAddress)

    SavedAddress.where(user_id: user.id).order(created_at: :desc)
  rescue
    []
  end
end
