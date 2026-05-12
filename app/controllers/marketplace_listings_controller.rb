class MarketplaceListingsController < ApplicationController
  class MarketplaceError < StandardError; end

  before_action :require_login!, except: [ :index, :show ]
  before_action :set_listing, only: [
    :show,
    :edit,
    :update,
    :create_offer,
    :accept_offer,
    :pay,
    :confirm_payment,
    :confirm_paid,
    :cancel,
    :destroy
  ]

  # Shows active listings or sold listings depending on the selected tab.
  def index
    @tab = params[:tab].to_s == "sold" ? "sold" : "current"
    @admin_can_delete = admin_user?

    prepare_filter_data

    if @tab == "sold"
      load_sold_listings
    else
      load_current_listings
    end
  end

  # Opens the create-listing form.
  def new
    prepare_filter_data
    @holdings = selectable_holdings
    @listing_form = listing_form_from_params
  end

  # Creates a listing from either a catalogue product or one of the user's holdings.
  def create
    prepare_filter_data
    @listing_form = listing_form_from_params

    price_cents = parse_price_cents(params[:price])
    return render_new_with_error("Price must be greater than 0.") if price_cents <= 0

    quantity = params[:quantity].to_i
    return render_new_with_error("Quantity must be at least 1.") if quantity <= 0

    if catalogue_mode?
      create_catalogue_listing!(price_cents, quantity)
    else
      create_holding_listing!(price_cents, quantity)
    end

    redirect_to marketplace_path, notice: "Listing created.", status: :see_other
  rescue MarketplaceError => e
    render_new_with_error(e.message)
  rescue ActiveRecord::RecordInvalid => e
    render_new_with_error(e.record.errors.full_messages.to_sentence)
  rescue
    render_new_with_error("Could not create listing.")
  end

  # Opens the edit form for the seller or an admin.
  def edit
    ensure_listing_can_be_edited!
    @condition_options = marketplace_conditions
  rescue MarketplaceError => e
    redirect_to marketplace_listing_path(@listing), alert: e.message, status: :see_other
  end

  # Updates price, quantity and condition.
  def update
    ensure_listing_can_be_edited!

    price_cents = parse_price_cents(params[:price])
    raise MarketplaceError, "Price must be greater than €0." if price_cents <= 0

    quantity = params[:quantity].to_i
    raise MarketplaceError, "Quantity must be at least 1." if quantity <= 0

    condition = params[:condition].to_s.strip
    raise MarketplaceError, "Condition is required." if condition.blank?

    ActiveRecord::Base.transaction do
      listing = MarketplaceListing.lock.find(@listing.id)
      update_holding_listed_quantity!(listing, quantity)

      listing.update!(
        price_cents: price_cents,
        quantity: quantity,
        condition: condition
      )
    end

    redirect_to marketplace_listing_path(@listing), notice: "Listing updated.", status: :see_other
  rescue MarketplaceError => e
    @condition_options = marketplace_conditions
    flash.now[:alert] = e.message
    render :edit, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    @condition_options = marketplace_conditions
    flash.now[:alert] = e.record.errors.full_messages.to_sentence
    render :edit, status: :unprocessable_entity
  rescue
    @condition_options = marketplace_conditions
    flash.now[:alert] = "Could not update listing."
    render :edit, status: :unprocessable_entity
  end

  # Shows one listing with seller and offer information.
  def show
    @admin_can_delete = admin_user?
    @is_seller = current_user && current_user.id.to_i == @listing.seller_id.to_i

    @my_offers =
      if current_user
        @listing.marketplace_offers.where(buyer_id: current_user.id).order(created_at: :desc).to_a
      else
        []
      end

    @has_active_offer = @my_offers.any? { |offer| %w[pending accepted paid confirmed_paid].include?(offer.status.to_s) }
    @can_offer = current_user.present? && !@is_seller && @listing.active? && !@has_active_offer
    @seller_offers = @is_seller ? @listing.marketplace_offers.includes(:buyer).order(created_at: :desc).to_a : []
  end

  # Buyer sends an offer to the seller.
  def create_offer
    offer_cents = parse_price_cents(params[:offer_amount])
    raise MarketplaceError, "Offer must be greater than €0." if offer_cents <= 0

    ActiveRecord::Base.transaction do
      listing = MarketplaceListing.lock.find(@listing.id)

      raise MarketplaceError, "This listing is not active." unless listing.active?
      raise MarketplaceError, "You cannot make an offer on your own listing." if listing.seller_id.to_i == current_user.id.to_i

      active_offer = MarketplaceOffer.lock.where(
        marketplace_listing_id: listing.id,
        buyer_id: current_user.id,
        status: %w[pending accepted paid confirmed_paid]
      ).exists?

      raise MarketplaceError, "You already have an active offer on this listing." if active_offer

      MarketplaceOffer.create!(
        marketplace_listing_id: listing.id,
        buyer_id: current_user.id,
        seller_id: listing.seller_id,
        offer_cents: offer_cents,
        status: "pending"
      )
    end

    redirect_to marketplace_listing_path(@listing), notice: "Offer sent.", status: :see_other
  rescue MarketplaceError => e
    redirect_to marketplace_listing_path(@listing), alert: e.message, status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_to marketplace_listing_path(@listing), alert: e.record.errors.full_messages.to_sentence, status: :see_other
  rescue
    redirect_to marketplace_listing_path(@listing), alert: "Could not send offer.", status: :see_other
  end

  # Seller accepts one pending offer and rejects the other open offers.
  def accept_offer
    ActiveRecord::Base.transaction do
      listing = MarketplaceListing.lock.find(@listing.id)
      offer = MarketplaceOffer.lock.find_by!(id: params[:offer_id], marketplace_listing_id: listing.id)

      raise MarketplaceError, "This listing is not active." unless listing.active?
      raise MarketplaceError, "You cannot accept offers for this listing." unless listing.seller_id.to_i == current_user.id.to_i
      raise MarketplaceError, "Only pending offers can be accepted." unless offer.pending?

      listing.marketplace_offers
             .where(status: %w[pending accepted])
             .where.not(id: offer.id)
             .update_all(status: "rejected", updated_at: Time.current)

      offer.update!(status: "accepted", accepted_at: Time.current)
    end

    redirect_to marketplace_listing_path(@listing), notice: "Offer accepted.", status: :see_other
  rescue MarketplaceError => e
    redirect_to marketplace_listing_path(@listing), alert: e.message, status: :see_other
  rescue
    redirect_to marketplace_listing_path(@listing), alert: "Could not accept offer.", status: :see_other
  end

  # Opens the manual Revolut payment page for an accepted offer.
  def pay
    raise MarketplaceError, "You cannot pay for your own listing." if @listing.seller_id.to_i == current_user.id.to_i

    @offer = MarketplaceOffer.find_by!(
      id: params[:offer_id],
      marketplace_listing_id: @listing.id,
      buyer_id: current_user.id
    )

    raise MarketplaceError, "This offer has not been accepted." unless @offer.accepted? || @offer.paid?

    @seller_revolut_tag = @listing.seller&.revolut_tag.to_s
  rescue MarketplaceError => e
    redirect_to marketplace_listing_path(@listing), alert: e.message, status: :see_other
  rescue
    redirect_to marketplace_listing_path(@listing), alert: "Could not open payment page.", status: :see_other
  end

  # Buyer confirms that the Revolut payment was sent.
  def confirm_payment
    ActiveRecord::Base.transaction do
      listing = MarketplaceListing.lock.find(@listing.id)
      raise MarketplaceError, "You cannot pay for your own listing." if listing.seller_id.to_i == current_user.id.to_i

      offer = MarketplaceOffer.lock.find_by!(
        id: params[:offer_id],
        marketplace_listing_id: listing.id,
        buyer_id: current_user.id
      )

      raise MarketplaceError, "This offer has not been accepted." unless offer.accepted?

      buyer_tag = current_user.revolut_tag.to_s.strip
      raise MarketplaceError, "Add your Revolut tag to your account before confirming payment." if buyer_tag.blank?

      offer.update!(
        buyer_revolut_tag: buyer_tag,
        status: "paid",
        paid_at: Time.current
      )
    end

    redirect_to marketplace_listing_path(@listing), notice: "Payment marked as sent. The seller must now confirm payment.", status: :see_other
  rescue MarketplaceError => e
    redirect_to marketplace_listing_path(@listing), alert: e.message, status: :see_other
  rescue
    redirect_to marketplace_listing_path(@listing), alert: "Could not confirm payment.", status: :see_other
  end

  # Seller confirms payment, moves the item into sold listings and adds it to the buyer portfolio.
  def confirm_paid
    ActiveRecord::Base.transaction do
      listing = MarketplaceListing.lock.find(@listing.id)
      offer = MarketplaceOffer.lock.find_by!(id: params[:offer_id], marketplace_listing_id: listing.id)

      raise MarketplaceError, "You cannot confirm payment for this listing." unless listing.seller_id.to_i == current_user.id.to_i
      raise MarketplaceError, "The buyer has not marked this payment as sent." unless offer.paid?

      seller = User.lock.find(listing.seller_id)
      buyer = User.lock.find(offer.buyer_id)

      quantity_sold = listing.quantity.to_i
      quantity_sold = 1 if quantity_sold <= 0

      unit_cents = offer.offer_cents.to_i / quantity_sold
      unit_cents = offer.offer_cents.to_i if unit_cents <= 0

      seller_holding = listing.holding_id.present? ? Holding.lock.find_by(id: listing.holding_id) : nil

      if seller_holding
        reduce_seller_holding!(seller_holding, quantity_sold)
        add_holding_to_buyer!(buyer, seller_holding, quantity_sold, unit_cents)
      else
        add_catalogue_listing_to_buyer!(buyer, listing, quantity_sold, unit_cents)
      end

      listing.update!(quantity: 0, status: "sold")
      offer.update!(status: "confirmed_paid", confirmed_paid_at: Time.current)

      listing.marketplace_offers
             .where(status: %w[pending accepted])
             .where.not(id: offer.id)
             .update_all(status: "rejected", updated_at: Time.current)

      create_purchase_log!(listing, buyer, seller, seller_holding, quantity_sold, unit_cents, offer.offer_cents.to_i)
    end

    redirect_to marketplace_path(tab: "sold"), notice: "Payment confirmed. Listing moved to Sold Listings.", status: :see_other
  rescue MarketplaceError => e
    redirect_to marketplace_listing_path(@listing), alert: e.message, status: :see_other
  rescue
    redirect_to marketplace_listing_path(@listing), alert: "Could not confirm payment.", status: :see_other
  end

  # Seller cancels an active listing and frees any listed holding quantity.
  def cancel
    ActiveRecord::Base.transaction do
      listing = MarketplaceListing.lock.find(@listing.id)

      raise MarketplaceError, "Only active listings can be deleted." unless listing.status.to_s == "active"
      raise MarketplaceError, "You cannot delete this listing." unless listing.seller_id.to_i == current_user.id.to_i

      release_listed_quantity!(listing)
      listing.marketplace_offers.where(status: %w[pending accepted]).update_all(status: "cancelled", updated_at: Time.current)
      listing.update!(status: "cancelled")
    end

    redirect_to marketplace_path, notice: "Listing deleted.", status: :see_other
  rescue MarketplaceError => e
    redirect_to marketplace_path, alert: e.message, status: :see_other
  rescue
    redirect_to marketplace_path, alert: "Could not delete listing.", status: :see_other
  end

  # Admin moves a listing into sold listings.
  def destroy
    return redirect_to(marketplace_path, alert: "Forbidden.", status: :see_other) unless admin_user?

    ActiveRecord::Base.transaction do
      listing = MarketplaceListing.lock.find(@listing.id)
      release_listed_quantity!(listing) if listing.status.to_s == "active"
      listing.marketplace_offers.where(status: %w[pending accepted]).update_all(status: "cancelled", updated_at: Time.current)
      listing.update!(status: "sold", quantity: 0)
    end

    redirect_to marketplace_path(tab: "sold"), notice: "Listing moved to Sold Listings.", status: :see_other
  rescue
    redirect_to marketplace_path, alert: "Could not delete listing.", status: :see_other
  end

  private

  # Finds the listing for member actions.
  def set_listing
    @listing = MarketplaceListing.includes(:seller).find(params[:id])
  end

  # Checks whether the logged-in user is an admin.
  def admin_user?
    return true if respond_to?(:admin_signed_in?) && admin_signed_in?
    current_user&.respond_to?(:admin?) && current_user.admin?
  rescue
    false
  end

  # Loads catalogue values for filters and create-listing dropdowns.
  def prepare_filter_data
    @sets_data = sets_data
    @eras = @sets_data.values.map { |set| set["era"].to_s }.reject(&:blank?).uniq.sort
    @sets_for_era = sets_for_era(params[:era])
    @condition_options = marketplace_conditions
  end

  # Reads the product catalogue from config/sets.json.
  def sets_data
    @sets_data ||= JSON.parse(File.read(Rails.root.join("config", "sets.json"), encoding: "bom|utf-8"))
  rescue
    {}
  end

  # Returns sets belonging to one selected era.
  def sets_for_era(era)
    return [] if era.to_s.blank?

    sets_data.values
             .select { |set| set["era"].to_s == era.to_s }
             .sort_by { |set| set["name"].to_s }
             .map { |set| { "slug" => set["slug"].to_s, "name" => set["name"].to_s } }
  end

  # Conditions used by marketplace create/edit forms.
  def marketplace_conditions
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

  # Keeps submitted values in the new-listing form after validation errors.
  def listing_form_from_params
    {
      mode: params[:mode].to_s.presence || params[:ml_mode_choice].to_s.presence || "catalog",
      holding_id: params[:holding_id].to_s,
      catalog_set_slug: params[:catalog_set_slug].to_s,
      catalog_route_type: params[:catalog_route_type].to_s,
      catalog_condition: params[:catalog_condition].to_s.presence || params[:holding_condition].to_s,
      price: params[:price].to_s,
      quantity: params[:quantity].to_s.presence || "1"
    }
  end

  # Re-renders the create-listing form with an error message.
  def render_new_with_error(message)
    @holdings = selectable_holdings
    @listing_form = listing_form_from_params
    flash.now[:alert] = message
    render :new, status: :unprocessable_entity
  end

  # Checks which listing mode the form is using.
  def catalogue_mode?
    params[:mode].to_s != "holding"
  end

  # Converts euro text into integer cents.
  def parse_price_cents(value)
    (BigDecimal(value.to_s.strip.tr(",", ".")) * 100).round.to_i
  rescue
    0
  end

  # Creates a listing directly from the product catalogue.
  def create_catalogue_listing!(price_cents, quantity)
    set_slug = params[:catalog_set_slug].to_s.strip
    route_type = params[:catalog_route_type].to_s.strip
    condition = params[:catalog_condition].to_s.strip

    raise MarketplaceError, "Choose a product." if set_slug.blank? || route_type.blank?
    raise MarketplaceError, "Choose a condition." if condition.blank?

    meta = listing_meta_for_slug_type(set_slug, route_type)

    ActiveRecord::Base.transaction do
      MarketplaceListing.create!(
        seller_id: current_user.id,
        holding_id: nil,
        product_sku: "#{set_slug}:#{route_type}",
        set_slug: set_slug,
        route_type: route_type,
        set_name: meta[:set_name],
        product_type_name: meta[:product_type_name],
        condition: condition,
        country_code: marketplace_country_code,
        price_cents: price_cents,
        quantity: quantity,
        status: "active"
      )
    end
  end

  # Creates a listing from a user's portfolio holding.
  def create_holding_listing!(price_cents, quantity)
    holding = Holding.find_by(id: params[:holding_id])
    raise MarketplaceError, "Choose a holding." unless holding
    raise MarketplaceError, "That holding is not yours." unless holding.user_id.to_i == current_user.id.to_i
    raise MarketplaceError, "This holding has no condition set." if holding.condition.to_s.blank?

    meta = listing_meta_for_holding(holding)

    ActiveRecord::Base.transaction do
      locked_holding = Holding.lock.find(holding.id)
      available = locked_holding.quantity.to_i - locked_holding.listed_quantity.to_i
      raise MarketplaceError, "Not enough available quantity." if quantity > available

      locked_holding.update!(listed_quantity: locked_holding.listed_quantity.to_i + quantity)

      MarketplaceListing.create!(
        seller_id: current_user.id,
        holding_id: locked_holding.id,
        product_sku: meta[:sku],
        set_slug: meta[:set_slug],
        route_type: meta[:route_type],
        set_name: meta[:set_name],
        product_type_name: meta[:product_type_name],
        condition: locked_holding.condition.to_s,
        country_code: marketplace_country_code,
        price_cents: price_cents,
        quantity: quantity,
        status: "active"
      )
    end
  end

  # Uses the seller account country, falling back to Ireland.
  def marketplace_country_code
    current_user.respond_to?(:country_code) && current_user.country_code.present? ? current_user.country_code.to_s : "IE"
  end

  # Only holdings with available quantity can be listed.
  def selectable_holdings
    Holding.where(user_id: current_user.id).select do |holding|
      holding.quantity.to_i - holding.listed_quantity.to_i > 0
    end
  end

  # Loads active listings.
  def load_current_listings
    scope = MarketplaceListing.active.includes(:seller)
    scope = apply_current_filters(scope)

    @listings = scope.to_a
    @sold_rows = []
    @sold_listing_map = {}
  end

  # Applies database filters to active listings.
  def apply_current_filters(scope)
    if params[:q].to_s.strip.present?
      term = "%#{params[:q].to_s.downcase.strip}%"

      scope = scope.joins(:seller).where(
        "LOWER(marketplace_listings.set_name) LIKE :term OR LOWER(marketplace_listings.product_type_name) LIKE :term OR LOWER(marketplace_listings.product_sku) LIKE :term OR LOWER(users.username) LIKE :term",
        term: term
      )
    end

    scope = scope.where(country_code: params[:country]) if params[:country].to_s.present?

    if params[:era].to_s.present?
      slugs = set_slugs_for_era(params[:era])
      scope = slugs.any? ? scope.where(set_slug: slugs) : scope.none
    end

    scope = scope.where(set_slug: params[:set_slug]) if params[:set_slug].to_s.present?

    if params[:product_type].to_s.present?
      type = params[:product_type].to_s
      scope = scope.where("route_type = ? OR route_type LIKE ?", type, "#{type}--%")
    end

    scope = scope.where(condition: params[:condition]) if params[:condition].to_s.present?
    scope = scope.where("price_cents >= ?", parse_price_cents(params[:min_price])) if parse_price_cents(params[:min_price]) > 0
    scope = scope.where("price_cents <= ?", parse_price_cents(params[:max_price])) if parse_price_cents(params[:max_price]) > 0

    case params[:sort].to_s
    when "oldest"
      scope.order(created_at: :asc)
    when "price-asc"
      scope.order(price_cents: :asc, created_at: :desc)
    when "price-desc"
      scope.order(price_cents: :desc, created_at: :desc)
    else
      scope.order(created_at: :desc)
    end
  end

  # Loads purchase rows plus sold listing rows for the sold tab.
  def load_sold_listings
    purchase_rows = MarketplacePurchase.order(created_at: :desc).limit(2000).to_a
    purchase_listing_ids = purchase_rows.map(&:marketplace_listing_id).compact.uniq

    sold_listings = MarketplaceListing.where(status: "sold").includes(:seller)
    sold_listings = sold_listings.where.not(id: purchase_listing_ids) if purchase_listing_ids.any?

    rows = purchase_rows + sold_listings.order(updated_at: :desc).limit(2000).to_a
    @sold_listing_map = MarketplaceListing.where(id: purchase_listing_ids).includes(:seller).index_by(&:id)
    rows = rows.select { |row| sold_row_matches_filters?(row) }
    rows = sort_sold_rows(rows)

    @sold_rows = rows.first(500)
    @listings = []
  end

  # Checks sold rows against the current filters.
  def sold_row_matches_filters?(row)
    searchable = [
      sold_row_seller_name(row),
      sold_row_set_name(row),
      sold_row_product_name(row),
      sold_row_product_sku(row)
    ].join(" ").downcase

    return false if params[:q].to_s.present? && !searchable.include?(params[:q].to_s.downcase.strip)
    return false if params[:country].to_s.present? && sold_row_country(row) != params[:country].to_s
    return false if params[:era].to_s.present? && set_era_for_slug(sold_row_set_slug(row)) != params[:era].to_s
    return false if params[:set_slug].to_s.present? && sold_row_set_slug(row) != params[:set_slug].to_s

    if params[:product_type].to_s.present?
      base_type = sold_row_route_type(row).split("--", 2).first
      return false unless base_type == params[:product_type].to_s
    end

    return false if params[:condition].to_s.present? && sold_row_condition(row) != params[:condition].to_s
    return false if parse_price_cents(params[:min_price]) > 0 && sold_row_unit_cents(row) < parse_price_cents(params[:min_price])
    return false if parse_price_cents(params[:max_price]) > 0 && sold_row_unit_cents(row) > parse_price_cents(params[:max_price])

    true
  end

  # Sorts sold rows by selected order.
  def sort_sold_rows(rows)
    case params[:sort].to_s
    when "oldest"
      rows.sort_by { |row| sold_row_date(row) || Time.at(0) }
    when "price-asc"
      rows.sort_by { |row| [ sold_row_unit_cents(row), -(sold_row_date(row)&.to_i || 0) ] }
    when "price-desc"
      rows.sort_by { |row| [ -sold_row_unit_cents(row), -(sold_row_date(row)&.to_i || 0) ] }
    else
      rows.sort_by { |row| -(sold_row_date(row)&.to_i || 0) }
    end
  end

  # Finds set slugs for an era.
  def set_slugs_for_era(era)
    sets_data.values.select { |set| set["era"].to_s == era.to_s }.map { |set| set["slug"].to_s }
  end

  # Finds an era by set slug.
  def set_era_for_slug(slug)
    set = sets_data[slug.to_s] || sets_data.values.find { |item| item["slug"].to_s == slug.to_s }
    set ? set["era"].to_s : ""
  end

  # Blocks edits once the listing is not active or offer/payment activity has started.
  def ensure_listing_can_be_edited!
    raise MarketplaceError, "You cannot edit this listing." unless @listing.seller_id.to_i == current_user.id.to_i || admin_user?
    raise MarketplaceError, "Only active listings can be edited." unless @listing.status.to_s == "active"
    raise MarketplaceError, "This listing cannot be edited because payment or sale activity has already started." if @listing.marketplace_offers.where(status: %w[accepted paid confirmed_paid]).exists?
  end

  # Keeps the holding listed quantity correct when listing quantity changes.
  def update_holding_listed_quantity!(listing, new_quantity)
    return if listing.holding_id.blank?

    holding = Holding.lock.find_by(id: listing.holding_id)
    return unless holding

    old_quantity = listing.quantity.to_i
    total_quantity = holding.quantity.to_i
    listed_quantity = holding.listed_quantity.to_i
    available = total_quantity - listed_quantity + old_quantity

    raise MarketplaceError, "Not enough available quantity in your holding." if new_quantity > available

    holding.update!(listed_quantity: listed_quantity - old_quantity + new_quantity)
  end

  # Releases listed quantity when a listing is cancelled or admin-deleted.
  def release_listed_quantity!(listing)
    return if listing.holding_id.blank?

    holding = Holding.lock.find_by(id: listing.holding_id)
    return unless holding

    new_listed = holding.listed_quantity.to_i - listing.quantity.to_i
    holding.update!(listed_quantity: [ new_listed, 0 ].max)
  end

  # Reduces the seller's holding after a confirmed sale.
  def reduce_seller_holding!(holding, quantity_sold)
    quantity = [ holding.quantity.to_i - quantity_sold, 0 ].max
    listed_quantity = [ holding.listed_quantity.to_i - quantity_sold, 0 ].max
    holding.update!(quantity: quantity, listed_quantity: listed_quantity)
  end

  # Adds a sold holding to the buyer's portfolio.
  def add_holding_to_buyer!(buyer, seller_holding, quantity, unit_cents)
    unit_price = unit_cents.to_i / 100.0
    existing = Holding.where(user_id: buyer.id, product_id: seller_holding.product_id).first

    if existing
      new_quantity = existing.quantity.to_i + quantity
      existing.update!(
        quantity: new_quantity,
        listed_quantity: 0,
        cost_per_unit: unit_price,
        total_cost: unit_price * new_quantity,
        purchase_date: Date.current
      )
      return
    end

    Holding.create!(
      user_id: buyer.id,
      product_id: seller_holding.product_id,
      username: buyer.username.to_s,
      era: seller_holding.era,
      set_name: seller_holding.set_name,
      product_type: seller_holding.product_type,
      condition: seller_holding.condition,
      quantity: quantity,
      listed_quantity: 0,
      cost_per_unit: unit_price,
      value: seller_holding.value,
      total_cost: unit_price * quantity,
      total_value: seller_holding.value.to_d * quantity,
      pl: 0,
      roi_pct: 0,
      purchase_date: Date.current,
      image: seller_holding.image
    )
  end

  # Adds a catalogue listing to the buyer's portfolio after purchase.
  def add_catalogue_listing_to_buyer!(buyer, listing, quantity, unit_cents)
    product = ensure_product_for_listing!(listing)
    unit_price = unit_cents.to_i / 100.0

    Holding.create!(
      user_id: buyer.id,
      product_id: product.id,
      username: buyer.username.to_s,
      era: set_era_for_slug(listing.set_slug),
      set_name: listing.set_name,
      product_type: listing.product_type_name,
      condition: listing.condition,
      quantity: quantity,
      listed_quantity: 0,
      cost_per_unit: unit_price,
      value: unit_price,
      total_cost: unit_price * quantity,
      total_value: unit_price * quantity,
      pl: 0,
      roi_pct: 0,
      purchase_date: Date.current,
      image: ""
    )
  end

  # Makes sure catalogue purchases have a Product row to link the buyer holding to.
  def ensure_product_for_listing!(listing)
    product = Product.find_by(sku: listing.product_sku.to_s)
    return product if product

    Product.create!(
      sku: listing.product_sku.to_s,
      name: listing.product_type_name.to_s,
      product_type: listing.route_type.to_s,
      set_name: listing.set_name.to_s,
      era: set_era_for_slug(listing.set_slug),
      value: listing.price_cents.to_i / 100.0
    )
  end

  # Stores a completed sale row for sold listings and realised P/L.
  def create_purchase_log!(listing, buyer, seller, seller_holding, quantity, unit_cents, total_cents)
    cost_cents = seller_holding ? (seller_holding.cost_per_unit.to_d * 100).round.to_i : nil
    realised_cents = cost_cents ? (unit_cents.to_i - cost_cents) * quantity.to_i : nil

    MarketplacePurchase.create!(
      buyer_id: buyer.id,
      seller_id: seller.id,
      marketplace_listing_id: listing.id,
      holding_id: seller_holding&.id,
      set_slug: listing.set_slug,
      route_type: listing.route_type,
      set_name: listing.set_name,
      product_name: listing.product_type_name,
      condition: listing.condition,
      quantity: quantity,
      unit_price_cents: unit_cents,
      total_price_cents: total_cents,
      seller_cost_per_unit_cents: cost_cents,
      realised_pl_cents: realised_cents,
      debug_id: SecureRandom.hex(8),
      debug_context: "manual_revolut_offer_payment"
    )
  end

  # Builds display metadata for a catalogue-created listing.
  def listing_meta_for_slug_type(slug, route_type)
    set = sets_data[slug.to_s] || sets_data.values.find { |item| item["slug"].to_s == slug.to_s }
    raise MarketplaceError, "Choose a valid set." unless set

    product = product_from_route(set, route_type)
    raise MarketplaceError, "Choose a valid product." unless product

    {
      set_name: set["name"].to_s,
      product_type_name: product["name"].to_s.presence || titleize_code(product["type"])
    }
  end

  # Builds display metadata for a holding-created listing.
  def listing_meta_for_holding(holding)
    sku = holding.product&.sku.to_s
    set_slug, route_type = parse_sku(sku)

    set_slug = slug_for_set_name(holding.set_name) if set_slug.blank?
    route_type = holding.product&.product_type.to_s if route_type.blank?
    route_type = title_to_code(holding.product_type) if route_type.blank?

    {
      sku: [ set_slug, route_type ].reject(&:blank?).join(":"),
      set_slug: set_slug,
      route_type: route_type,
      set_name: holding.set_name.to_s,
      product_type_name: holding.product_type.to_s
    }
  end

  # Finds a catalogue product from route type.
  def product_from_route(set, route_type)
    parsed = parse_route_type(route_type)

    Array(set["products"] || set["sealed"]).find do |product|
      type = product["type"].to_s
      name = product["name"].to_s

      next false unless normalize_type(type) == parsed[:base_type]
      next false if parsed[:variant_slug].present? && slugify(extract_variant(name)) != parsed[:variant_slug]
      next false if parsed[:origin_slug].present? && slugify(infer_origin(type, name)) != parsed[:origin_slug]
      next false if parsed[:product_slug].present? && slugify(name) != parsed[:product_slug]

      true
    end
  end

  # Splits route type values such as etb--v-lucario.
  def parse_route_type(route_type)
    parts = route_type.to_s.split("--")

    out = {
      base_type: normalize_type(parts.shift),
      variant_slug: nil,
      origin_slug: nil,
      product_slug: nil
    }

    parts.each do |part|
      out[:variant_slug] = part.delete_prefix("v-") if part.start_with?("v-")
      out[:origin_slug] = part.delete_prefix("o-") if part.start_with?("o-")
      out[:product_slug] = part.delete_prefix("p-") if part.start_with?("p-")
    end

    out
  end

  # Parses SKU values in slug:type format.
  def parse_sku(sku)
    text = sku.to_s
    return text.split(":", 2) if text.include?(":")
    return text.split("--", 2) if text.include?("--")

    [ text, "" ]
  end

  # Finds a set slug from a set name.
  def slug_for_set_name(set_name)
    set = sets_data.values.find { |item| item["name"].to_s == set_name.to_s }
    set ? set["slug"].to_s : ""
  end

  # Converts text product type to a basic route code.
  def title_to_code(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
  end

  # Converts code text into title case.
  def titleize_code(value)
    value.to_s.tr("_", " ").tr("-", " ").split.map(&:capitalize).join(" ")
  end

  # Normalises product route type codes.
  def normalize_type(value)
    value.to_s.downcase.tr("-", "_").strip
  end

  # Normalises text for slug matching.
  def normalize_text(value)
    value.to_s.unicode_normalize(:nfkc).downcase.strip.gsub(/\s+/, " ")
  end

  # Converts text into a route slug.
  def slugify(value)
    normalize_text(value).gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
  end

  # Pulls variant text from product names.
  def extract_variant(name)
    name.to_s[/\(([^)]+)\)/, 1].to_s.strip
  end

  # Detects Pokemon Center products.
  def infer_origin(type, name)
    return "Pokemon Center" if normalize_type(type) == "pc_etb"
    return "Pokemon Center" if normalize_text(name).include?("pokemon center")

    ""
  end

  # Finds the listing behind a sold purchase row.
  def sold_listing_for(row)
    return row if row.is_a?(MarketplaceListing)
    @sold_listing_map[row.marketplace_listing_id.to_i] if row.respond_to?(:marketplace_listing_id)
  end

  # Sold row helpers keep filters short and readable.
  def sold_row_set_slug(row)
    row.respond_to?(:set_slug) && row.set_slug.present? ? row.set_slug.to_s : sold_listing_for(row)&.set_slug.to_s
  end

  def sold_row_route_type(row)
    row.respond_to?(:route_type) && row.route_type.present? ? row.route_type.to_s : sold_listing_for(row)&.route_type.to_s
  end

  def sold_row_condition(row)
    row.respond_to?(:condition) && row.condition.present? ? row.condition.to_s : sold_listing_for(row)&.condition.to_s
  end

  def sold_row_country(row)
    row.respond_to?(:country_code) && row.country_code.present? ? row.country_code.to_s : sold_listing_for(row)&.country_code.to_s
  end

  def sold_row_unit_cents(row)
    return row.unit_price_cents.to_i if row.respond_to?(:unit_price_cents) && row.unit_price_cents.to_i > 0
    return row.price_cents.to_i if row.respond_to?(:price_cents) && row.price_cents.to_i > 0

    sold_listing_for(row)&.price_cents.to_i
  end

  def sold_row_date(row)
    row.created_at || sold_listing_for(row)&.updated_at
  end

  def sold_row_seller_id(row)
    row.respond_to?(:seller_id) && row.seller_id.present? ? row.seller_id : sold_listing_for(row)&.seller_id
  end

  def sold_row_seller_name(row)
    seller = User.find_by(id: sold_row_seller_id(row))
    seller&.username.to_s
  rescue
    ""
  end

  def sold_row_set_name(row)
    row.respond_to?(:set_name) && row.set_name.present? ? row.set_name.to_s : sold_listing_for(row)&.set_name.to_s
  end

  def sold_row_product_name(row)
    return row.product_name.to_s if row.respond_to?(:product_name) && row.product_name.present?
    return row.product_type_name.to_s if row.respond_to?(:product_type_name) && row.product_type_name.present?

    sold_listing_for(row)&.product_type_name.to_s
  end

  def sold_row_product_sku(row)
    row.respond_to?(:product_sku) && row.product_sku.present? ? row.product_sku.to_s : sold_listing_for(row)&.product_sku.to_s
  end
end
