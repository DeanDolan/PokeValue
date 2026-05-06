class MarketplaceListingEditsController < ApplicationController
  helper_method :current_user

  # Opens the edit listing form for the seller or an admin
  def edit
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    @listing = MarketplaceListing.includes(:seller).find(params[:id])

    unless can_edit_listing?(@listing)
      return redirect_to(marketplace_listing_path(@listing), alert: "You cannot edit this listing.")
    end

    unless @listing.status.to_s == "active"
      return redirect_to(marketplace_listing_path(@listing), alert: "Only active listings can be edited.")
    end

    if @listing.marketplace_offers.where(status: [ "accepted", "paid", "confirmed_paid" ]).exists?
      return redirect_to(marketplace_listing_path(@listing), alert: "This listing cannot be edited because payment or sale activity has already started.")
    end

    @condition_options = condition_options

    render "marketplace_listings/edit"
  end

  # Updates safe editable listing fields without touching payment, offers or sold listing logic
  def update
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    listing = nil

    ActiveRecord::Base.transaction do
      listing = MarketplaceListing.lock.find(params[:id])

      unless can_edit_listing?(listing)
        raise "not_allowed"
      end

      unless listing.status.to_s == "active"
        raise "listing_not_active"
      end

      if listing.marketplace_offers.where(status: [ "accepted", "paid", "confirmed_paid" ]).exists?
        raise "listing_has_sale_activity"
      end

      price_cents = parse_price_cents(params[:price])
      raise "invalid_price" if price_cents <= 0

      quantity = params[:quantity].to_i
      raise "invalid_quantity" if quantity <= 0

      condition = params[:condition].to_s.strip
      raise "invalid_condition" if condition.blank?

      uploads = Array(params[:photos]).compact.reject { |f| f.respond_to?(:blank?) && f.blank? }
      validate_uploads!(listing, uploads)

      update_holding_listed_quantity!(listing, quantity)

      listing.update!(
        price_cents: price_cents,
        quantity: quantity,
        condition: condition
      )

      uploads.each { |file| listing.photos.attach(file) } if uploads.any?
    end

    redirect_to marketplace_listing_path(listing), notice: "Listing updated."
  rescue => e
    @listing = MarketplaceListing.includes(:seller).find_by(id: params[:id])
    @condition_options = condition_options

    if @listing
      flash.now[:alert] = edit_error_message(e)
      render "marketplace_listings/edit", status: :unprocessable_entity
    else
      redirect_to marketplace_path, alert: "Could not update listing."
    end
  end

  private

  # Finds the logged-in user from the session
  def current_user
    return @current_user if defined?(@current_user)
    @current_user = User.find_by(id: session[:user_id])
  end

  # Allows the seller or an admin to edit an active listing
  def can_edit_listing?(listing)
    return false unless current_user
    return true if listing.seller_id.to_i == current_user.id.to_i
    return true if admin_can_manage_marketplace?

    false
  rescue
    false
  end

  # Allows admins to manage listings they do not own
  def admin_can_manage_marketplace?
    ok = false

    begin
      ok = true if respond_to?(:admin_signed_in?) && admin_signed_in?
    rescue
    end

    return true if ok

    return false unless current_user

    return true if current_user.respond_to?(:admin?) && current_user.admin?
    return true if current_user.respond_to?(:admin) && !!current_user.admin

    false
  rescue
    false
  end

  # Condition dropdown used by the edit form
  def condition_options
    [
      "Mint Condition",
      "Mint Sealed",
      "Loosely Sealed",
      "Unsealed",
      "Big Tear",
      "Small Tear",
      "Mini Tear/Hole (<2cm)",
      "Small Tear (>2cm)",
      "Big Tear (>1 inch)",
      "Big Imperfections",
      "Small Imperfections",
      "Pressure Marks",
      "Slightly Dented",
      "Heavy Dented",
      "Damaged",
      "Box Only",
      "Contents Only"
    ].uniq
  end

  # Converts the submitted euro price into cents
  def parse_price_cents(raw)
    value = BigDecimal(raw.to_s.strip.tr(",", "."))
    (value * 100).round.to_i
  rescue
    0
  end

  # Validates uploaded listing photos before attaching them
  def validate_uploads!(listing, uploads)
    return if uploads.blank?

    current_count =
      if listing.respond_to?(:photos) && listing.photos.respond_to?(:attached?) && listing.photos.attached?
        listing.photos.count
      else
        0
      end

    if current_count + uploads.length > 4
      raise "too_many_photos"
    end

    uploads.each do |file|
      content_type = file.content_type.to_s

      unless content_type == "image/png" || content_type == "image/jpeg" || content_type == "image/jpg"
        raise "invalid_photo_type"
      end
    end
  end

  # Keeps holding listed quantity accurate when the seller edits quantity
  def update_holding_listed_quantity!(listing, new_quantity)
    return if listing.holding_id.blank?
    return unless defined?(Holding)

    holding = Holding.lock.find_by(id: listing.holding_id)
    return unless holding
    return unless holding.respond_to?(:listed_quantity)

    old_quantity = listing.quantity.to_i
    listed_quantity = holding.listed_quantity.to_i
    total_quantity = holding.respond_to?(:quantity) ? holding.quantity.to_i : 0

    available_for_this_listing = total_quantity - listed_quantity + old_quantity
    available_for_this_listing = 0 if available_for_this_listing < 0

    raise "not_enough_available_quantity" if new_quantity > available_for_this_listing

    new_listed_quantity = listed_quantity - old_quantity + new_quantity
    new_listed_quantity = 0 if new_listed_quantity < 0

    if holding.respond_to?(:listed_quantity=)
      holding.update!(listed_quantity: new_listed_quantity)
    end
  end

  # Converts internal edit errors into user-friendly flash messages
  def edit_error_message(error)
    message = error.message.to_s

    case message
    when "not_allowed"
      "You cannot edit this listing."
    when "listing_not_active"
      "Only active listings can be edited."
    when "listing_has_sale_activity"
      "This listing cannot be edited because payment or sale activity has already started."
    when "invalid_price"
      "Price must be greater than €0."
    when "invalid_quantity"
      "Quantity must be at least 1."
    when "invalid_condition"
      "Condition is required."
    when "too_many_photos"
      "A listing can only have up to 4 images."
    when "invalid_photo_type"
      "Images must be JPG or PNG."
    when "not_enough_available_quantity"
      "Not enough available quantity in your holding."
    else
      "Could not update listing."
    end
  end
end
