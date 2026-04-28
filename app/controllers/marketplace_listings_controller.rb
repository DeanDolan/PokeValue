class MarketplaceListingsController < ApplicationController
  helper_method :current_user

  def index
    @tab = params[:tab].to_s == "sold" ? "sold" : "current"
    prepare_filter_data

    if @tab == "sold"
      load_sold_index_rows
    else
      load_current_index_rows
    end
  end

  def new
    return redirect_to(root_path, alert: "Please log in.") unless current_user
    @holdings = selectable_holdings
    @listing_form = listing_form_from_params
  end

  def create
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    @listing_form = listing_form_from_params

    country_code =
      if current_user.respond_to?(:country_code) && current_user.country_code.present?
        current_user.country_code.to_s
      else
        "IE"
      end

    price_str = params[:price].to_s.strip

    begin
      price = BigDecimal(price_str.tr(",", "."))
    rescue
      return render_new_with_error("Enter a valid price.")
    end

    price_cents = (price * 100).round
    return render_new_with_error("Price must be greater than 0.") if price_cents <= 0

    qty = params[:quantity].to_i
    return render_new_with_error("Quantity must be at least 1.") if qty <= 0

    uploads = Array(params[:photos]).compact.reject { |f| f.respond_to?(:blank?) && f.blank? }
    return render_new_with_error("You can upload up to 4 images.") if uploads.length > 4

    uploads.each do |f|
      ct = f.content_type.to_s
      unless ct == "image/png" || ct == "image/jpeg" || ct == "image/jpg"
        return render_new_with_error("Images must be .jpg or .png.")
      end
    end

    is_catalog = params[:mode].to_s.strip == "catalog"
    listing = nil

    ActiveRecord::Base.transaction do
      if is_catalog
        set_slug = params[:catalog_set_slug].to_s.strip
        type_code = params[:catalog_route_type].to_s.strip
        return render_new_with_error("Choose a product.") if set_slug.blank? || type_code.blank?

        condition = params[:catalog_condition].to_s.strip
        return render_new_with_error("Choose a condition.") if condition.blank?

        meta = listing_meta_for_slug_type(set_slug, type_code)

        listing = MarketplaceListing.create!(
          seller_id: current_user.id,
          holding_id: nil,
          product_sku: "#{set_slug}:#{type_code}",
          set_slug: set_slug,
          route_type: type_code,
          set_name: meta[:set_name],
          product_type_name: meta[:product_type_name],
          condition: condition,
          country_code: country_code,
          price_cents: price_cents,
          quantity: qty,
          status: "active"
        )
      else
        holding = Holding.find_by(id: params[:holding_id])
        return render_new_with_error("Invalid holding.") unless holding
        return render_new_with_error("That holding is not yours.") unless holding.respond_to?(:user_id) && holding.user_id == current_user.id

        condition =
          if holding.respond_to?(:condition) && holding.condition.present?
            holding.condition.to_s
          else
            ""
          end

        return render_new_with_error("This holding has no condition set.") if condition.blank?

        meta = listing_meta_for_holding(holding)

        h = Holding.lock.find(holding.id)
        h_qty = h.respond_to?(:quantity) ? h.quantity.to_i : 0
        h_listed = h.respond_to?(:listed_quantity) ? h.listed_quantity.to_i : 0
        available = h_qty - h_listed
        return render_new_with_error("Not enough available quantity.") if qty > available

        h.update!(listed_quantity: h_listed + qty)

        listing = MarketplaceListing.create!(
          seller_id: current_user.id,
          holding_id: h.id,
          product_sku: meta[:sku],
          set_slug: meta[:slug],
          route_type: meta[:type_code],
          set_name: meta[:set_name],
          product_type_name: meta[:product_type_name],
          condition: condition,
          country_code: country_code,
          price_cents: price_cents,
          quantity: qty,
          status: "active"
        )
      end

      if listing && listing.respond_to?(:photos) && listing.photos.respond_to?(:attach) && uploads.any?
        uploads.each { |f| listing.photos.attach(f) }
      end
    end

    redirect_to(marketplace_path, notice: "Listing created.")
  rescue ActiveRecord::RecordInvalid => e
    msg =
      if e.respond_to?(:record) && e.record && e.record.respond_to?(:errors) && e.record.errors.any?
        e.record.errors.full_messages.join(", ")
      else
        "Could not create listing."
      end

    render_new_with_error(msg)
  rescue
    render_new_with_error("Could not create listing.")
  end

  def show
    @listing = MarketplaceListing.includes(:seller, marketplace_offers: [ :buyer ]).find(params[:id])

    @seller_stats =
      if defined?(Review)
        avg = Review.where(seller_id: @listing.seller_id).average(:rating).to_f
        cnt = Review.where(seller_id: @listing.seller_id).count
        { avg: avg, count: cnt }
      else
        { avg: 0.0, count: 0 }
      end

    @recent_reviews =
      if defined?(Review)
        Review.where(seller_id: @listing.seller_id).order(created_at: :desc).limit(10)
      else
        []
      end

    @admin_can_delete = admin_can_manage_marketplace?
    @is_seller = current_user && current_user.id.to_i == @listing.seller_id.to_i
    @my_offers = current_user ? @listing.marketplace_offers.where(buyer_id: current_user.id).order(created_at: :desc).to_a : []
    @has_active_offer = @my_offers.any? { |offer| %w[pending accepted paid confirmed_paid].include?(offer.status.to_s) }
    @can_offer = current_user.present? && !@is_seller && @listing.active? && !@has_active_offer
    @seller_offers = @is_seller ? @listing.marketplace_offers.includes(:buyer).order(created_at: :desc).to_a : []
  end

  def checkout
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    @listing = MarketplaceListing.includes(:seller).find(params[:id])

    if @listing.seller_id.to_i == current_user.id.to_i
      return redirect_to(marketplace_listing_path(@listing), alert: "You cannot purchase your own product.")
    end

    unless @listing.status.to_s == "active"
      return redirect_to(marketplace_listing_path(@listing), alert: "This listing is not active.")
    end

    @quantity = params[:quantity].to_i
    @quantity = 1 if @quantity <= 0
    max_qty = @listing.respond_to?(:quantity) ? @listing.quantity.to_i : 1
    max_qty = 1 if max_qty <= 0
    @quantity = max_qty if @quantity > max_qty

    @address = address_from_params
    @saved_addresses = load_saved_addresses(current_user)
    @seller_stats =
      if defined?(Review)
        avg = Review.where(seller_id: @listing.seller_id).average(:rating).to_f
        cnt = Review.where(seller_id: @listing.seller_id).count
        { avg: avg, count: cnt }
      else
        { avg: 0.0, count: 0 }
      end
  rescue
    redirect_to marketplace_path, alert: "Could not open checkout."
  end

  def buy
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    @listing = MarketplaceListing.includes(:seller).find(params[:id])

    if @listing.seller_id.to_i == current_user.id.to_i
      return redirect_to(marketplace_listing_path(@listing), alert: "You cannot purchase your own product.")
    end

    unless @listing.status.to_s == "active"
      return redirect_to(marketplace_listing_path(@listing), alert: "This listing is not active.")
    end

    @quantity = params[:quantity].to_i
    @quantity = 1 if @quantity <= 0
    max_qty = @listing.respond_to?(:quantity) ? @listing.quantity.to_i : 1
    max_qty = 1 if max_qty <= 0
    @quantity = max_qty if @quantity > max_qty

    @address = address_from_params
    @saved_addresses = load_saved_addresses(current_user)
    @seller_stats =
      if defined?(Review)
        avg = Review.where(seller_id: @listing.seller_id).average(:rating).to_f
        cnt = Review.where(seller_id: @listing.seller_id).count
        { avg: avg, count: cnt }
      else
        { avg: 0.0, count: 0 }
      end

    return render_checkout_with_error("Full name is required.") if @address[:name].blank?
    return render_checkout_with_error("Address Line 1 is required.") if @address[:line1].blank?
    return render_checkout_with_error("City/Town is required.") if @address[:city].blank?
    return render_checkout_with_error("County/State is required.") if @address[:county].blank?
    return render_checkout_with_error("Eircode is required.") if @address[:postcode].blank?
    return render_checkout_with_error("Country is required.") if @address[:country_code].blank?

    redirect_to marketplace_listing_path(@listing), alert: "Purchases now use the offer system."
  rescue
    if defined?(@listing) && @listing
      @address ||= address_from_params
      @saved_addresses ||= load_saved_addresses(current_user)
      @seller_stats ||= { avg: 0.0, count: 0 }
      render_checkout_with_error("Could not complete purchase.")
    else
      redirect_to marketplace_path, alert: "Could not complete purchase."
    end
  end

  def create_offer
    return redirect_to(root_path, alert: "Please log in.", status: :see_other) unless current_user

    listing = nil
    error_message = nil

    ActiveRecord::Base.transaction do
      listing = MarketplaceListing.lock.find(params[:id])

      unless listing.active?
        error_message = "This listing is not active."
        raise ActiveRecord::Rollback
      end

      if listing.seller_id.to_i == current_user.id.to_i
        error_message = "You cannot make an offer on your own listing."
        raise ActiveRecord::Rollback
      end

      existing_active_offer = MarketplaceOffer.lock.where(
        marketplace_listing_id: listing.id,
        buyer_id: current_user.id,
        status: [ "pending", "accepted", "paid", "confirmed_paid" ]
      ).first

      if existing_active_offer
        error_message = "You already have an active offer on this listing."
        raise ActiveRecord::Rollback
      end

      offer_amount = params[:offer_amount].to_s.strip

      begin
        offer_cents = (BigDecimal(offer_amount.tr(",", ".")) * 100).round
      rescue
        offer_cents = 0
      end

      if offer_cents <= 0
        error_message = "Offer must be greater than €0."
        raise ActiveRecord::Rollback
      end

      MarketplaceOffer.create!(
        marketplace_listing_id: listing.id,
        buyer_id: current_user.id,
        seller_id: listing.seller_id,
        offer_cents: offer_cents,
        status: "pending"
      )
    end

    if error_message.present?
      redirect_to marketplace_listing_path(listing || params[:id]), alert: error_message, status: :see_other
    else
      redirect_to marketplace_listing_path(listing), notice: "Offer sent.", status: :see_other
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_to marketplace_listing_path(params[:id]), alert: e.record.errors.full_messages.to_sentence, status: :see_other
  rescue
    redirect_to marketplace_listing_path(params[:id]), alert: "Could not send offer.", status: :see_other
  end

  def accept_offer
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    ActiveRecord::Base.transaction do
      listing = MarketplaceListing.lock.find(params[:id])
      offer = MarketplaceOffer.lock.find_by!(id: params[:offer_id], marketplace_listing_id: listing.id)

      unless listing.active?
        raise "listing_not_active"
      end

      unless listing.seller_id.to_i == current_user.id.to_i
        raise "not_seller"
      end

      unless offer.pending?
        raise "offer_not_pending"
      end

      listing.marketplace_offers.where(status: [ "pending", "accepted" ]).where.not(id: offer.id).update_all(status: "rejected", updated_at: Time.current)

      offer.update!(
        status: "accepted",
        accepted_at: Time.current
      )
    end

    redirect_to marketplace_listing_path(params[:id]), notice: "Offer accepted."
  rescue
    redirect_to marketplace_listing_path(params[:id]), alert: "Could not accept offer."
  end

  def pay
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    @listing = MarketplaceListing.includes(:seller).find(params[:id])

    if @listing.seller_id.to_i == current_user.id.to_i
      return redirect_to(marketplace_listing_path(@listing), alert: "You cannot pay for your own listing.")
    end

    @offer = MarketplaceOffer.find_by!(id: params[:offer_id], marketplace_listing_id: @listing.id, buyer_id: current_user.id)

    unless @offer.accepted? || @offer.paid?
      return redirect_to marketplace_listing_path(@listing), alert: "This offer has not been accepted."
    end

    @seller_revolut_tag = @listing.seller&.revolut_tag.to_s
  rescue
    redirect_to marketplace_listing_path(params[:id]), alert: "Could not open payment page."
  end

  def confirm_payment
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    ActiveRecord::Base.transaction do
      listing = MarketplaceListing.lock.find(params[:id])
      raise "cannot_pay_own_listing" if listing.seller_id.to_i == current_user.id.to_i

      offer = MarketplaceOffer.lock.find_by!(id: params[:offer_id], marketplace_listing_id: listing.id, buyer_id: current_user.id)

      unless offer.accepted?
        raise "offer_not_accepted"
      end

      buyer_revolut_tag = current_user.revolut_tag.to_s.strip
      raise "missing_revolut_tag" if buyer_revolut_tag.blank?

      offer.buyer_revolut_tag = buyer_revolut_tag
      offer.status = "paid"
      offer.paid_at = Time.current
      offer.save!
    end

    redirect_to marketplace_listing_path(params[:id]), notice: "Payment marked as sent. The seller must now confirm payment."
  rescue
    redirect_to marketplace_listing_path(params[:id]), alert: "Could not confirm payment."
  end

  def confirm_paid
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    ActiveRecord::Base.transaction do
      listing = MarketplaceListing.lock.find(params[:id])
      offer = MarketplaceOffer.lock.find_by!(id: params[:offer_id], marketplace_listing_id: listing.id)

      unless listing.seller_id.to_i == current_user.id.to_i
        raise "not_seller"
      end

      unless offer.paid?
        raise "offer_not_paid"
      end

      seller = User.lock.find(listing.seller_id)
      buyer = User.lock.find(offer.buyer_id)

      qty_sold = listing.quantity.to_i
      qty_sold = 1 if qty_sold <= 0

      unit_cents = offer.offer_cents.to_i / qty_sold
      unit_cents = offer.offer_cents.to_i if unit_cents <= 0

      if listing.holding_id.present?
        seller_holding = Holding.lock.find_by(id: listing.holding_id)

        if seller_holding && seller_holding.respond_to?(:user_id) && seller_holding.user_id.to_i == seller.id.to_i
          sh_qty = seller_holding.respond_to?(:quantity) ? seller_holding.quantity.to_i : 0
          sh_listed = seller_holding.respond_to?(:listed_quantity) ? seller_holding.listed_quantity.to_i : 0

          new_qty = sh_qty - qty_sold
          new_qty = 0 if new_qty < 0

          new_listed = sh_listed - qty_sold
          new_listed = 0 if new_listed < 0

          attrs = {}
          attrs[:quantity] = new_qty if seller_holding.respond_to?(:quantity=)
          attrs[:listed_quantity] = new_listed if seller_holding.respond_to?(:listed_quantity=)

          seller_holding.update!(attrs) if attrs.any?
          add_to_buyer_holdings_safe(buyer, seller_holding, qty_sold, unit_cents, SecureRandom.hex(8))
        end
      else
        add_catalog_to_buyer_holdings_safe(buyer, listing, qty_sold, unit_cents, SecureRandom.hex(8))
      end

      listing.update!(
        quantity: 0,
        status: "sold"
      )

      offer.update!(
        status: "confirmed_paid",
        confirmed_paid_at: Time.current
      )

      listing.marketplace_offers.where(status: [ "pending", "accepted" ]).where.not(id: offer.id).update_all(status: "rejected", updated_at: Time.current)

      create_purchase_log_safe(listing, buyer, seller, qty_sold, unit_cents, offer.offer_cents.to_i, {}, SecureRandom.hex(8))
    end

    redirect_to marketplace_path(tab: "sold"), notice: "Payment confirmed. Listing moved to Sold Listings."
  rescue
    redirect_to marketplace_listing_path(params[:id]), alert: "Could not confirm payment."
  end

  def cancel
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    ActiveRecord::Base.transaction do
      listing = MarketplaceListing.lock.find(params[:id])
      raise "invalid" unless listing.status.to_s == "active"
      raise "invalid" unless listing.seller_id == current_user.id

      if listing.holding_id.present?
        h = Holding.lock.find(listing.holding_id)
        h_listed = h.respond_to?(:listed_quantity) ? h.listed_quantity.to_i : 0
        new_listed = h_listed - listing.quantity.to_i
        new_listed = 0 if new_listed < 0
        h.update!(listed_quantity: new_listed) if h.respond_to?(:listed_quantity=)
      end

      listing.marketplace_offers.where(status: [ "pending", "accepted" ]).update_all(status: "cancelled", updated_at: Time.current)
      listing.update!(status: "cancelled")
    end

    redirect_to(marketplace_path, notice: "Listing cancelled.")
  rescue
    redirect_to(marketplace_path, alert: "Could not cancel listing.")
  end

  def destroy
    return redirect_to(marketplace_path, alert: "Forbidden.") unless admin_can_manage_marketplace?

    debug_id = SecureRandom.hex(8)

    begin
      ActiveRecord::Base.transaction do
        listing = MarketplaceListing.lock.find_by(id: params[:id])
        unless listing
          next
        end

        if listing.status.to_s == "active" && listing.respond_to?(:holding_id) && listing.holding_id.present?
          h = Holding.lock.find_by(id: listing.holding_id)
          if h && h.respond_to?(:listed_quantity)
            h_listed = h.listed_quantity.to_i
            dec = listing.respond_to?(:quantity) ? listing.quantity.to_i : 0
            new_listed = h_listed - dec
            new_listed = 0 if new_listed < 0

            begin
              h.update!(listed_quantity: new_listed) if h.respond_to?(:listed_quantity=)
            rescue
              begin
                h.update_columns(listed_quantity: new_listed) if h.respond_to?(:listed_quantity)
              rescue
              end
            end
          end
        end

        listing.marketplace_offers.where(status: [ "pending", "accepted" ]).update_all(status: "cancelled", updated_at: Time.current)

        attrs = { status: "deleted", updated_at: Time.current }
        attrs[:quantity] = 0 if listing.respond_to?(:quantity)
        listing.update_columns(attrs)
      end
    rescue => e
      Rails.logger.error("ADMIN_LISTING_DELETE_FAILED [#{debug_id}] #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
      return redirect_to(marketplace_path, alert: "Could not delete listing. [#{debug_id}]")
    end

    redirect_to(marketplace_path, notice: "Listing deleted.")
  end

  private

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

  def render_new_with_error(message)
    @holdings = selectable_holdings
    @listing_form = listing_form_from_params
    flash.now[:alert] = message
    render :new, status: :unprocessable_entity
  end

  def render_checkout_with_error(message)
    flash.now[:alert] = message
    @address ||= address_from_params
    @saved_addresses ||= load_saved_addresses(current_user)
    @seller_stats ||= { avg: 0.0, count: 0 }
    render :checkout, status: :unprocessable_entity
  end

  def address_from_params
    raw = params[:address]
    h =
      if raw.is_a?(ActionController::Parameters)
        raw.to_unsafe_h
      elsif raw.is_a?(Hash)
        raw
      else
        {}
      end

    {
      name: h["name"].to_s.strip,
      line1: h["line1"].to_s.strip,
      line2: h["line2"].to_s.strip,
      city: h["city"].to_s.strip,
      county: h["county"].to_s.strip,
      postcode: h["postcode"].to_s.strip,
      country_code: h["country_code"].to_s.strip
    }
  rescue
    { name: "", line1: "", line2: "", city: "", county: "", postcode: "", country_code: "" }
  end

  def load_saved_addresses(user)
    return [] unless user
    return [] unless defined?(SavedAddress)
    return [] unless SavedAddress.respond_to?(:table_name)
    return [] unless ActiveRecord::Base.connection.data_source_exists?(SavedAddress.table_name)

    SavedAddress.where(user_id: user.id).order(created_at: :desc).limit(5).to_a
  rescue
    []
  end

  def prepare_filter_data
    data = sets_data
    @eras = data.values.map { |s| s["era"].to_s }.reject(&:blank?).uniq.sort

    selected_era = params[:era].to_s.strip
    @sets_for_era =
      if selected_era.present?
        data.values
            .select { |s| s["era"].to_s == selected_era }
            .sort_by { |s| s["name"].to_s }
            .map { |s| { "slug" => s["slug"].to_s, "name" => s["name"].to_s } }
      else
        []
      end

    @condition_options = [
      "Mint Condition",
      "Loosely Sealed",
      "Unsealed",
      "Big Tear",
      "Small Tear",
      "Big Imperfections",
      "Small Imperfections",
      "Pressure Marks",
      "Slightly Dented",
      "Heavy Dented",
      "Damaged",
      "Box Only",
      "Contents Only"
    ]
  end

  def load_current_index_rows
    scope = MarketplaceListing.active.includes(:seller)
    scope = apply_current_scope_filters(scope)

    @listings = scope.to_a
    @sold_rows = []
    @sold_listing_map = {}
    @review_stats = review_stats_for_seller_ids(@listings.map(&:seller_id).uniq)
  end

  def load_sold_index_rows
    if marketplace_purchase_available?
      scope = MarketplacePurchase.all

      if col_exists?(MarketplacePurchase, "status")
        scope = scope.where(status: "sold")
      elsif col_exists?(MarketplacePurchase, "refunded")
        scope = scope.where(refunded: false)
      elsif col_exists?(MarketplacePurchase, "refunded_at")
        scope = scope.where(refunded_at: nil)
      end

      rows = scope.order(created_at: :desc).limit(2000).to_a
      @sold_listing_map = build_sold_listing_map(rows)
      rows = apply_sold_row_filters(rows, @sold_listing_map)
      @sold_rows = rows.first(500)
    else
      rows = MarketplaceListing.where(status: "sold").includes(:seller).order(updated_at: :desc).limit(2000).to_a
      @sold_listing_map = {}
      rows = apply_sold_row_filters(rows, @sold_listing_map)
      @sold_rows = rows.first(500)
    end

    @listings = []
    seller_ids = @sold_rows.map { |row| seller_id_for_sold_row(row, @sold_listing_map) }.compact.uniq
    @review_stats = review_stats_for_seller_ids(seller_ids)
  end

  def apply_current_scope_filters(scope)
    q = params[:q].to_s.strip
    if q.present?
      term = "%#{q.downcase}%"
      scope = scope.joins(:seller).where(
        "LOWER(marketplace_listings.set_name) LIKE :t OR LOWER(marketplace_listings.product_type_name) LIKE :t OR LOWER(marketplace_listings.product_sku) LIKE :t OR LOWER(users.username) LIKE :t",
        t: term
      )
    end

    country = params[:country].to_s.strip
    scope = scope.where(country_code: country) if country.present?

    era = params[:era].to_s.strip
    if era.present?
      slugs = set_slugs_for_era(era)
      scope = slugs.any? ? scope.where(set_slug: slugs) : scope.where(id: nil)
    end

    set_slug = params[:set_slug].to_s.strip
    scope = scope.where(set_slug: set_slug) if set_slug.present?

    product_type = params[:product_type].to_s.strip
    if product_type.present?
      scope = scope.where("route_type = ? OR route_type LIKE ?", product_type, "#{product_type}--v-%")
    end

    condition = params[:condition].to_s.strip
    scope = scope.where(condition: condition) if condition.present?

    min_price = params[:min_price].to_s.strip
    if min_price.present?
      begin
        min_cents = (BigDecimal(min_price) * 100).to_i
        scope = scope.where("price_cents >= ?", min_cents)
      rescue
      end
    end

    max_price = params[:max_price].to_s.strip
    if max_price.present?
      begin
        max_cents = (BigDecimal(max_price) * 100).to_i
        scope = scope.where("price_cents <= ?", max_cents)
      rescue
      end
    end

    case params[:sort].to_s.strip
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

  def apply_sold_row_filters(rows, listing_map)
    filtered = Array(rows).select { |row| sold_row_matches_filters?(row, listing_map) }

    case params[:sort].to_s.strip
    when "oldest"
      filtered.sort_by { |row| sold_row_date(row, listing_map) || Time.at(0) }
    when "price-asc"
      filtered.sort_by { |row| [ sold_row_unit_cents(row, listing_map), -(sold_row_date(row, listing_map)&.to_i || 0) ] }
    when "price-desc"
      filtered.sort_by { |row| [ -sold_row_unit_cents(row, listing_map), -(sold_row_date(row, listing_map)&.to_i || 0) ] }
    else
      filtered.sort_by { |row| -(sold_row_date(row, listing_map)&.to_i || 0) }
    end
  end

  def sold_row_matches_filters?(row, listing_map)
    listing = sold_listing_for_row(row, listing_map)

    q = params[:q].to_s.strip.downcase
    if q.present?
      seller_name =
        if row.respond_to?(:seller_id) && row.seller_id.present?
          seller = User.find_by(id: row.seller_id)
          seller&.respond_to?(:username) ? seller.username.to_s.downcase : ""
        elsif listing&.respond_to?(:seller) && listing.seller&.respond_to?(:username)
          listing.seller.username.to_s.downcase
        else
          ""
        end

      set_name =
        if row.respond_to?(:set_name) && row.set_name.present?
          row.set_name.to_s.downcase
        elsif listing&.respond_to?(:set_name) && listing.set_name.present?
          listing.set_name.to_s.downcase
        else
          ""
        end

      product_name =
        if row.respond_to?(:product_type_name) && row.product_type_name.present?
          row.product_type_name.to_s.downcase
        elsif row.respond_to?(:product_name) && row.product_name.present?
          row.product_name.to_s.downcase
        elsif listing&.respond_to?(:product_type_name) && listing.product_type_name.present?
          listing.product_type_name.to_s.downcase
        else
          ""
        end

      product_sku =
        if row.respond_to?(:product_sku) && row.product_sku.present?
          row.product_sku.to_s.downcase
        elsif listing&.respond_to?(:product_sku) && listing.product_sku.present?
          listing.product_sku.to_s.downcase
        else
          ""
        end

      haystack = [ seller_name, set_name, product_name, product_sku ].join(" ")
      return false unless haystack.include?(q)
    end

    country = params[:country].to_s.strip
    if country.present?
      return false unless sold_row_country_code(row, listing_map).to_s == country
    end

    era = params[:era].to_s.strip
    if era.present?
      slug = sold_row_set_slug(row, listing_map).to_s
      row_era = set_era_for_slug(slug)
      return false unless row_era == era
    end

    set_slug = params[:set_slug].to_s.strip
    if set_slug.present?
      return false unless sold_row_set_slug(row, listing_map).to_s == set_slug
    end

    product_type = params[:product_type].to_s.strip
    if product_type.present?
      route_type = sold_row_route_type(row, listing_map).to_s
      base_route = route_type.split("--v-", 2).first.to_s
      return false unless base_route == product_type
    end

    condition = params[:condition].to_s.strip
    if condition.present?
      return false unless sold_row_condition(row, listing_map).to_s == condition
    end

    min_price = params[:min_price].to_s.strip
    if min_price.present?
      begin
        min_cents = (BigDecimal(min_price) * 100).to_i
        return false if sold_row_unit_cents(row, listing_map) < min_cents
      rescue
      end
    end

    max_price = params[:max_price].to_s.strip
    if max_price.present?
      begin
        max_cents = (BigDecimal(max_price) * 100).to_i
        return false if sold_row_unit_cents(row, listing_map) > max_cents
      rescue
      end
    end

    true
  end

  def sold_row_set_slug(row, listing_map)
    if row.respond_to?(:set_slug) && row.set_slug.present?
      row.set_slug.to_s
    else
      listing = sold_listing_for_row(row, listing_map)
      listing&.respond_to?(:set_slug) ? listing.set_slug.to_s : ""
    end
  end

  def sold_row_route_type(row, listing_map)
    if row.respond_to?(:route_type) && row.route_type.present?
      row.route_type.to_s
    else
      listing = sold_listing_for_row(row, listing_map)
      listing&.respond_to?(:route_type) ? listing.route_type.to_s : ""
    end
  end

  def sold_row_condition(row, listing_map)
    if row.respond_to?(:condition) && row.condition.present?
      row.condition.to_s
    else
      listing = sold_listing_for_row(row, listing_map)
      listing&.respond_to?(:condition) ? listing.condition.to_s : ""
    end
  end

  def sold_row_country_code(row, listing_map)
    if row.respond_to?(:country_code) && row.country_code.present?
      row.country_code.to_s
    else
      listing = sold_listing_for_row(row, listing_map)
      listing&.respond_to?(:country_code) ? listing.country_code.to_s : ""
    end
  end

  def sold_row_unit_cents(row, listing_map)
    if row.respond_to?(:unit_price_cents) && row.unit_price_cents.to_i > 0
      row.unit_price_cents.to_i
    elsif row.respond_to?(:price_cents) && row.price_cents.to_i > 0
      row.price_cents.to_i
    else
      listing = sold_listing_for_row(row, listing_map)
      listing&.respond_to?(:price_cents) ? listing.price_cents.to_i : 0
    end
  end

  def sold_row_date(row, listing_map)
    if row.respond_to?(:created_at) && row.created_at.present?
      row.created_at
    elsif row.respond_to?(:updated_at) && row.updated_at.present?
      row.updated_at
    else
      listing = sold_listing_for_row(row, listing_map)
      if listing&.respond_to?(:updated_at) && listing.updated_at.present?
        listing.updated_at
      else
        nil
      end
    end
  end

  def seller_id_for_sold_row(row, listing_map)
    if row.respond_to?(:seller_id) && row.seller_id.present?
      row.seller_id
    else
      listing = sold_listing_for_row(row, listing_map)
      listing&.seller_id
    end
  end

  def sold_listing_for_row(row, listing_map)
    if row.respond_to?(:marketplace_listing_id) && row.marketplace_listing_id.present?
      listing_map[row.marketplace_listing_id.to_i]
    elsif row.respond_to?(:listing_id) && row.listing_id.present?
      listing_map[row.listing_id.to_i]
    elsif row.is_a?(MarketplaceListing)
      row
    else
      nil
    end
  end

  def build_sold_listing_map(rows)
    ids = []

    Array(rows).each do |row|
      if row.respond_to?(:marketplace_listing_id) && row.marketplace_listing_id.present?
        ids << row.marketplace_listing_id.to_i
      elsif row.respond_to?(:listing_id) && row.listing_id.present?
        ids << row.listing_id.to_i
      end
    end

    ids.uniq!
    return {} if ids.empty?

    MarketplaceListing.where(id: ids).includes(:seller).index_by(&:id)
  rescue
    {}
  end

  def review_stats_for_seller_ids(ids)
    return {} unless defined?(Review)
    return {} if ids.blank?

    Review.where(seller_id: ids)
          .group(:seller_id)
          .pluck(:seller_id, Arel.sql("AVG(rating)"), Arel.sql("COUNT(*)"))
          .each_with_object({}) do |(sid, avg, cnt), h|
            h[sid] = { avg: avg.to_f, count: cnt.to_i }
          end
  rescue
    {}
  end

  def marketplace_purchase_available?
    return false unless defined?(MarketplacePurchase)
    return false unless MarketplacePurchase.respond_to?(:table_name)

    ActiveRecord::Base.connection.data_source_exists?(MarketplacePurchase.table_name)
  rescue
    false
  end

  def col_exists?(model, col)
    return false unless model
    return false unless model.respond_to?(:table_name)

    ActiveRecord::Base.connection.column_exists?(model.table_name, col.to_s)
  rescue
    false
  end

  def set_slugs_for_era(era)
    sets_data.values
             .select { |s| s["era"].to_s == era.to_s }
             .map { |s| s["slug"].to_s }
             .reject(&:blank?)
  rescue
    []
  end

  def set_era_for_slug(slug)
    s = sets_data[slug.to_s] || sets_data.values.find { |x| x["slug"].to_s == slug.to_s }
    s ? s["era"].to_s : ""
  rescue
    ""
  end

  def current_user
    return @current_user if defined?(@current_user)
    @current_user = User.find_by(id: session[:user_id])
  end

  def admin_can_manage_marketplace?
    ok = false

    begin
      ok = true if respond_to?(:admin_signed_in?) && admin_signed_in?
    rescue
    end

    return true if ok

    cu = current_user
    return false unless cu

    return true if cu.respond_to?(:admin?) && cu.admin?
    return true if cu.respond_to?(:admin) && !!cu.admin

    false
  rescue
    false
  end

  def selectable_holdings
    hs = Holding.where(user_id: current_user.id).to_a

    hs.select do |h|
      q = h.respond_to?(:quantity) ? h.quantity.to_i : 0
      lq = h.respond_to?(:listed_quantity) ? h.listed_quantity.to_i : 0
      (q - lq) > 0
    end
  end

  def sets_data
    raw = File.read(Rails.root.join("config", "sets.json"), encoding: "bom|utf-8")
    JSON.parse(raw)
  rescue
    {}
  end

  def type_map
    {
      "etb" => "Elite Trainer Box",
      "pc_etb" => "Pokemon Center Elite Trainer Box",
      "booster_box" => "Booster Box",
      "booster_bundle" => "Booster Bundle",
      "booster_bundle_display" => "Booster Bundle Display",
      "enhanced_booster_box" => "Enhanced Booster Box",
      "ultra_premium_collection" => "Ultra Premium Collection",
      "upc" => "Ultra Premium Collection",
      "spc" => "Super Premium Collection",
      "mini_tin" => "Mini Tin",
      "mini_tin_display" => "Mini Tin Display"
    }
  end

  def parse_sku(sku)
    s = sku.to_s

    if s.include?(":")
      a, b = s.split(":", 2)
      return [ a.to_s, b.to_s ]
    end

    if s.include?("--")
      a, b = s.split("--", 2)
      return [ a.to_s, b.to_s ]
    end

    [ s.to_s, "" ]
  end

  def split_type_variant(type_code)
    t = type_code.to_s

    if t.include?("--v-")
      base, raw = t.split("--v-", 2)
      variant = raw.to_s.tr("-", " ").split.map(&:capitalize).join(" ")
      return [ base.to_s, variant ]
    end

    [ t.to_s, "" ]
  end

  def titleize_code(code)
    code.to_s.tr("_", " ").tr("-", " ").split.map(&:capitalize).join(" ")
  end

  def normalize_name_to_type_and_variant(name, base_name)
    n = name.to_s.strip
    b = base_name.to_s.strip
    return [ b, "" ] if n.blank?

    if n.downcase.start_with?(b.downcase)
      variant = n[b.length..-1].to_s.strip

      if variant.start_with?("(") && variant.end_with?(")")
        variant = variant[1..-2].to_s.strip
      end

      return [ b, variant.presence || "" ]
    end

    if n.downcase.end_with?(b.downcase)
      variant = n[0...(n.length - b.length)].to_s.strip
      variant = variant.sub(/\(([^)]+)\)\s*$/) { Regexp.last_match(1).to_s }.strip if variant.include?("(") && variant.include?(")")
      variant = variant.sub(/[-–—]\s*$/, "").strip
      variant = variant.presence || ""
      return [ b, variant ]
    end

    extracted = n[/\(([^)]+)\)/, 1].to_s.strip

    if extracted.present?
      return [ b, extracted ]
    end

    [ b, "" ]
  end

  def listing_meta_for_slug_type(slug, type_code)
    s = sets_data[slug.to_s] || sets_data.values.find { |x| x["slug"].to_s == slug.to_s }
    set_name = s ? s["name"].to_s : slug.to_s

    base, variant = split_type_variant(type_code)
    base_name = type_map[base.to_s] || titleize_code(base)

    json_name = ""

    if s
      products = Array(s["products"] || s["sealed"])
      candidates = products.select { |p| p["type"].to_s == base.to_s }

      if variant.present?
        c = candidates.find { |p| p["name"].to_s.downcase.include?(variant.downcase) }
        json_name = c ? c["name"].to_s : ""
      else
        json_name = candidates.first ? candidates.first["name"].to_s : ""
      end
    end

    tn, vn =
      if json_name.present?
        normalize_name_to_type_and_variant(json_name, base_name)
      else
        [ base_name, variant.to_s ]
      end

    product_type_name = vn.present? ? "#{tn} (#{vn})" : tn
    { set_name: set_name, product_type_name: product_type_name }
  end

  def listing_meta_for_holding(holding)
    sku =
      if holding.respond_to?(:sku) && holding.sku.present?
        holding.sku.to_s
      elsif holding.respond_to?(:product_sku) && holding.product_sku.present?
        holding.product_sku.to_s
      elsif holding.respond_to?(:product) && holding.product && holding.product.respond_to?(:sku) && holding.product.sku.present?
        holding.product.sku.to_s
      else
        ""
      end

    slug =
      if holding.respond_to?(:set_slug) && holding.set_slug.present?
        holding.set_slug.to_s
      else
        parse_sku(sku)[0].to_s
      end

    type_code =
      if holding.respond_to?(:route_type) && holding.route_type.present?
        holding.route_type.to_s
      else
        parse_sku(sku)[1].to_s
      end

    base, type_variant = split_type_variant(type_code)

    holding_variant =
      if holding.respond_to?(:variant) && holding.variant.present?
        holding.variant.to_s
      elsif holding.respond_to?(:variant_name) && holding.variant_name.present?
        holding.variant_name.to_s
      elsif holding.respond_to?(:product_variant) && holding.product_variant.present?
        holding.product_variant.to_s
      else
        ""
      end

    variant = holding_variant.presence || type_variant.to_s

    s = sets_data[slug] || sets_data.values.find { |x| x["slug"].to_s == slug }
    set_name = s ? s["name"].to_s : slug.to_s
    base_name = type_map[base.to_s] || titleize_code(base)

    json_name = ""

    if s
      products = Array(s["products"] || s["sealed"])
      candidates = products.select { |p| p["type"].to_s == base.to_s }

      if variant.present?
        c = candidates.find { |p| p["name"].to_s.downcase.include?(variant.downcase) }
        json_name = c ? c["name"].to_s : ""
      else
        json_name = candidates.first ? candidates.first["name"].to_s : ""
      end
    end

    tn, vn =
      if json_name.present?
        normalize_name_to_type_and_variant(json_name, base_name)
      else
        [ base_name, variant.to_s ]
      end

    product_type_name = vn.present? ? "#{tn} (#{vn})" : tn

    {
      sku: (sku.presence || "#{slug}:#{type_code}"),
      slug: slug,
      type_code: type_code,
      set_name: set_name,
      product_type_name: product_type_name
    }
  end

  def create_purchase_log_safe(listing, buyer, seller, qty, unit_cents, total_cents, addr, debug_id)
    return unless defined?(MarketplacePurchase)

    cols = MarketplacePurchase.column_names rescue []
    return if cols.empty?

    attrs = {}

    attrs["marketplace_listing_id"] = listing.id if cols.include?("marketplace_listing_id")
    attrs["listing_id"] = listing.id if cols.include?("listing_id")
    attrs["buyer_id"] = buyer.id if cols.include?("buyer_id")
    attrs["seller_id"] = seller.id if seller && cols.include?("seller_id")
    attrs["holding_id"] = listing.holding_id if cols.include?("holding_id") && listing.respond_to?(:holding_id)
    attrs["quantity"] = qty if cols.include?("quantity")
    attrs["unit_price_cents"] = unit_cents if cols.include?("unit_price_cents")
    attrs["price_cents"] = unit_cents if cols.include?("price_cents")
    attrs["total_cents"] = total_cents if cols.include?("total_cents")
    attrs["total_price_cents"] = total_cents if cols.include?("total_price_cents")
    attrs["status"] = "sold" if cols.include?("status")
    attrs["debug_id"] = debug_id if cols.include?("debug_id")
    attrs["debug_context"] = "manual_revolut_offer_payment" if cols.include?("debug_context")

    attrs["set_slug"] = listing.set_slug.to_s if cols.include?("set_slug") && listing.respond_to?(:set_slug)
    attrs["route_type"] = listing.route_type.to_s if cols.include?("route_type") && listing.respond_to?(:route_type)
    attrs["set_name"] = listing.set_name.to_s if cols.include?("set_name") && listing.respond_to?(:set_name)
    attrs["product_name"] = listing.product_type_name.to_s if cols.include?("product_name") && listing.respond_to?(:product_type_name)
    attrs["condition"] = listing.condition.to_s if cols.include?("condition") && listing.respond_to?(:condition)

    if cols.include?("shipping_name") && addr[:name].present?
      attrs["shipping_name"] = addr[:name]
    elsif cols.include?("address_name") && addr[:name].present?
      attrs["address_name"] = addr[:name]
    end

    if cols.include?("address_line1") && addr[:line1].present?
      attrs["address_line1"] = addr[:line1]
    elsif cols.include?("shipping_line1") && addr[:line1].present?
      attrs["shipping_line1"] = addr[:line1]
    elsif cols.include?("line1") && addr[:line1].present?
      attrs["line1"] = addr[:line1]
    end

    if cols.include?("address_line2") && addr[:line2].present?
      attrs["address_line2"] = addr[:line2]
    elsif cols.include?("shipping_line2") && addr[:line2].present?
      attrs["shipping_line2"] = addr[:line2]
    elsif cols.include?("line2") && addr[:line2].present?
      attrs["line2"] = addr[:line2]
    end

    if cols.include?("address_city") && addr[:city].present?
      attrs["address_city"] = addr[:city]
    elsif cols.include?("shipping_city") && addr[:city].present?
      attrs["shipping_city"] = addr[:city]
    elsif cols.include?("city") && addr[:city].present?
      attrs["city"] = addr[:city]
    end

    if cols.include?("address_county") && addr[:county].present?
      attrs["address_county"] = addr[:county]
    elsif cols.include?("shipping_county") && addr[:county].present?
      attrs["shipping_county"] = addr[:county]
    elsif cols.include?("county") && addr[:county].present?
      attrs["county"] = addr[:county]
    end

    if cols.include?("address_postcode") && addr[:postcode].present?
      attrs["address_postcode"] = addr[:postcode]
    elsif cols.include?("shipping_postcode") && addr[:postcode].present?
      attrs["shipping_postcode"] = addr[:postcode]
    elsif cols.include?("postcode") && addr[:postcode].present?
      attrs["postcode"] = addr[:postcode]
    end

    if cols.include?("address_country_code") && addr[:country_code].present?
      attrs["address_country_code"] = addr[:country_code]
    elsif cols.include?("shipping_country_code") && addr[:country_code].present?
      attrs["shipping_country_code"] = addr[:country_code]
    elsif cols.include?("country_code") && addr[:country_code].present?
      attrs["country_code"] = addr[:country_code]
    end

    rec = MarketplacePurchase.new(attrs)

    begin
      rec.save!
    rescue => e
      Rails.logger.error("PURCHASE_LOG_SAVE_FAILED [#{debug_id}] #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n")) if e.backtrace

      begin
        rec.save(validate: false)
      rescue => e2
        Rails.logger.error("PURCHASE_LOG_SAVE_VALIDATE_FALSE_FAILED [#{debug_id}] #{e2.class}: #{e2.message}")
        Rails.logger.error(e2.backtrace.join("\n")) if e2.backtrace
      end
    end
  end

  def add_catalog_to_buyer_holdings_safe(buyer, listing, qty, unit_price_cents, debug_id)
    return unless defined?(Holding)
    return unless Holding.column_names.include?("user_id") && Holding.column_names.include?("quantity")

    cols = Holding.column_names
    product = ensure_product_for_listing(listing)

    return if cols.include?("product_id") && product.nil?

    attrs = {}
    attrs["user_id"] = buyer.id if cols.include?("user_id")
    attrs["username"] = buyer.username.to_s if cols.include?("username") && buyer.respond_to?(:username)
    attrs["product_id"] = product.id if product && cols.include?("product_id")
    attrs["quantity"] = qty if cols.include?("quantity")
    attrs["listed_quantity"] = 0 if cols.include?("listed_quantity")
    attrs["condition"] = listing.condition.to_s if cols.include?("condition") && listing.respond_to?(:condition)
    attrs["set_name"] = listing.set_name.to_s if cols.include?("set_name") && listing.respond_to?(:set_name)
    attrs["product_type"] = listing.product_type_name.to_s if cols.include?("product_type") && listing.respond_to?(:product_type_name)
    attrs["cost_per_unit"] = unit_price_cents / 100.0 if cols.include?("cost_per_unit")
    attrs["purchase_date"] = Date.current if cols.include?("purchase_date")
    attrs["value"] = unit_price_cents / 100.0 if cols.include?("value")
    attrs["total_cost"] = (unit_price_cents * qty) / 100.0 if cols.include?("total_cost")
    attrs["total_value"] = (unit_price_cents * qty) / 100.0 if cols.include?("total_value")
    attrs["pl"] = 0 if cols.include?("pl")
    attrs["roi_pct"] = 0 if cols.include?("roi_pct")

    existing = nil

    if product && cols.include?("product_id")
      existing = Holding.lock.where(user_id: buyer.id, product_id: product.id).first
    end

    if existing
      begin
        existing.update!(quantity: existing.quantity.to_i + qty)
      rescue => e
        Rails.logger.error("BUYER_HOLDING_UPDATE_FAILED [#{debug_id}] #{e.class}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n")) if e.backtrace

        begin
          existing.update_columns(quantity: existing.quantity.to_i + qty)
        rescue
        end
      end
    else
      rec = Holding.new(attrs.slice(*cols))

      begin
        rec.save!
      rescue => e
        Rails.logger.error("BUYER_HOLDING_CREATE_FAILED [#{debug_id}] #{e.class}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n")) if e.backtrace

        begin
          rec.save(validate: false)
        rescue
        end
      end
    end
  end

  def add_to_buyer_holdings_safe(buyer, seller_holding, qty, unit_price_cents, debug_id)
    return unless defined?(Holding)
    return unless Holding.column_names.include?("user_id") && Holding.column_names.include?("quantity")

    cols = Holding.column_names
    sku_col = cols.include?("product_sku") ? "product_sku" : (cols.include?("sku") ? "sku" : nil)

    attrs = {}
    attrs["user_id"] = buyer.id
    attrs["username"] = buyer.username.to_s if cols.include?("username") && buyer.respond_to?(:username)
    attrs["quantity"] = qty
    attrs["listed_quantity"] = 0 if cols.include?("listed_quantity")

    if sku_col
      v =
        if seller_holding.respond_to?(sku_col) && seller_holding.public_send(sku_col).present?
          seller_holding.public_send(sku_col)
        elsif seller_holding.respond_to?(:product_sku) && seller_holding.product_sku.present?
          seller_holding.product_sku
        elsif seller_holding.respond_to?(:sku) && seller_holding.sku.present?
          seller_holding.sku
        end

      attrs[sku_col] = v.to_s if v.present?
    end

    if cols.include?("product_id") && seller_holding.respond_to?(:product_id) && seller_holding.product_id.present?
      attrs["product_id"] = seller_holding.product_id
    end

    copy_cols = cols - %w[id user_id username quantity listed_quantity created_at updated_at]
    copy_cols.each do |c|
      next if attrs.key?(c)
      next unless seller_holding.respond_to?(c)
      attrs[c] = seller_holding.public_send(c)
    end

    attrs["cost_per_unit"] = unit_price_cents / 100.0 if cols.include?("cost_per_unit")
    attrs["purchase_date"] = Date.current if cols.include?("purchase_date")
    attrs["total_cost"] = (unit_price_cents * qty) / 100.0 if cols.include?("total_cost")
    attrs["total_value"] = (unit_price_cents * qty) / 100.0 if cols.include?("total_value")
    attrs["value"] = unit_price_cents / 100.0 if cols.include?("value")
    attrs["pl"] = 0 if cols.include?("pl")
    attrs["roi_pct"] = 0 if cols.include?("roi_pct")

    finder = { "user_id" => buyer.id }
    finder["product_id"] = attrs["product_id"] if attrs["product_id"]
    finder[sku_col] = attrs[sku_col] if sku_col && attrs[sku_col].present?

    existing = nil

    if finder.keys.length > 1
      existing = Holding.lock.where(finder).first
    end

    if existing
      begin
        existing.update!(quantity: existing.quantity.to_i + qty)
      rescue => e
        Rails.logger.error("BUYER_HOLDING_UPDATE_FAILED [#{debug_id}] #{e.class}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n")) if e.backtrace

        begin
          existing.update_columns(quantity: existing.quantity.to_i + qty)
        rescue
        end
      end
    else
      rec = Holding.new(attrs.slice(*cols))

      begin
        rec.save!
      rescue => e
        Rails.logger.error("BUYER_HOLDING_CREATE_FAILED [#{debug_id}] #{e.class}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n")) if e.backtrace

        begin
          rec.save(validate: false)
        rescue
        end
      end
    end
  end

  def ensure_product_for_listing(listing)
    return nil unless defined?(Product)

    sku = listing.product_sku.to_s.strip
    product = Product.find_by(sku: sku) if sku.present?
    return product if product

    attrs = {}

    attrs[:sku] = sku if Product.column_names.include?("sku")
    attrs[:set_name] = listing.set_name.to_s if Product.column_names.include?("set_name") && listing.respond_to?(:set_name)
    attrs[:product_type] = listing.product_type_name.to_s if Product.column_names.include?("product_type") && listing.respond_to?(:product_type_name)
    attrs[:name] = listing.product_type_name.to_s if Product.column_names.include?("name") && listing.respond_to?(:product_type_name)
    attrs[:value] = listing.price_cents.to_i / 100.0 if Product.column_names.include?("value") && listing.respond_to?(:price_cents)

    era = set_era_for_slug(listing.set_slug.to_s)
    attrs[:era] = era if Product.column_names.include?("era") && era.present?

    product = Product.new(attrs)

    begin
      product.save!
    rescue
      begin
        product.save(validate: false)
      rescue
        return nil
      end
    end

    product
  rescue
    nil
  end
end
