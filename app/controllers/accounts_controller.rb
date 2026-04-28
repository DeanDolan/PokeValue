class AccountsController < ApplicationController
  before_action :ensure_logged_in

  def show
    @user =
      if params[:id].present?
        User.find_by(id: params[:id])
      else
        current_user
      end

    return redirect_to(root_path, alert: "User not found.") unless @user

    @is_self = current_user && current_user.id == @user.id

    @tab = params[:tab].to_s.strip
    @tab = "current" if @tab.blank?
    @tab = "current" unless %w[current sold bought refunded].include?(@tab)

    @watchlist_items = []
    if @is_self
      @watchlist_items =
        if @user.respond_to?(:watchlists)
          @user.watchlists.order(created_at: :desc)
        elsif @user.respond_to?(:watchlist_items)
          @user.watchlist_items.order(created_at: :desc)
        else
          []
        end
    end

    @current_listings =
      if defined?(MarketplaceListing)
        scope =
          if MarketplaceListing.respond_to?(:active)
            MarketplaceListing.active
          else
            MarketplaceListing.where(status: "active")
          end
        scope.where(seller_id: @user.id).order(created_at: :desc)
      else
        []
      end

    @sold_sales = []
    @refunds_issued = []
    @refunds_received = []

    return unless @is_self
    return unless defined?(MarketplacePurchase)
    return unless table_exists?(MarketplacePurchase)

    if col_exists?(MarketplacePurchase, "seller_id")
      base = MarketplacePurchase.where(seller_id: @user.id).order(created_at: :desc).limit(500).to_a
      refunded, not_refunded = base.partition { |p| refunded_purchase?(p) }
      @refunds_issued = refunded
      @sold_sales = not_refunded
    end

    if col_exists?(MarketplacePurchase, "buyer_id")
      base = MarketplacePurchase.where(buyer_id: @user.id).order(created_at: :desc).limit(500).to_a
      @refunds_received = base.select { |p| refunded_purchase?(p) }
    end
  end

  def refund
    return redirect_to(root_path, alert: "Please log in.") unless current_user
    return redirect_to(account_path, alert: "Not available.") unless defined?(MarketplacePurchase)
    return redirect_to(account_path, alert: "Not available.") unless table_exists?(MarketplacePurchase)

    @purchase = MarketplacePurchase.find_by(id: params[:id])
    return redirect_to(account_path, alert: "Not found.") unless @purchase

    return redirect_to(account_path, alert: "Forbidden.") unless col_exists?(MarketplacePurchase, "seller_id") && @purchase.seller_id.to_i == current_user.id

    @buyer =
      if col_exists?(MarketplacePurchase, "buyer_id")
        User.find_by(id: @purchase.buyer_id)
      else
        nil
      end

    @listing = resolve_listing_for_purchase(@purchase)
    @address = purchase_address_hash(@purchase)
    @amount_cents = purchase_total_cents(@purchase).to_i
    @already_refunded = refunded_purchase?(@purchase)
  end

  def process_refund
    return redirect_to(root_path, alert: "Please log in.") unless current_user
    return redirect_to(account_path, alert: "Not available.") unless defined?(MarketplacePurchase)
    return redirect_to(account_path, alert: "Not available.") unless table_exists?(MarketplacePurchase)

    purchase = MarketplacePurchase.find_by(id: params[:id])
    return redirect_to(account_path, alert: "Not found.") unless purchase

    return redirect_to(account_path, alert: "Forbidden.") unless col_exists?(MarketplacePurchase, "seller_id") && purchase.seller_id.to_i == current_user.id

    note = params[:note].to_s
    debug_id = SecureRandom.hex(8)

    begin
      ActiveRecord::Base.transaction do
        p = MarketplacePurchase.lock.find(purchase.id)

        raise "already_refunded" if refunded_purchase?(p)

        seller = User.lock.find(current_user.id)
        buyer =
          if col_exists?(MarketplacePurchase, "buyer_id") && p.respond_to?(:buyer_id)
            User.lock.find_by(id: p.buyer_id)
          else
            nil
          end

        total_cents = purchase_total_cents(p).to_i
        raise "bad_amount" if total_cents <= 0

        seller_funds = user_funds_cents(seller)
        new_seller = seller_funds - total_cents
        new_seller = 0 if new_seller < 0
        update_user_funds_cents!(seller, new_seller)

        if buyer
          buyer_funds = user_funds_cents(buyer)
          update_user_funds_cents!(buyer, buyer_funds + total_cents)
        end

        persisted = persist_refund!(p, debug_id: debug_id, note: note, amount_cents: total_cents)
        raise "refund_not_persisted" unless persisted
      end
    rescue => e
      Rails.logger.error("REFUND_TOPLEVEL_FAILED [#{debug_id}] #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
      snapshot_refund_state(tag: "toplevel_rescue", debug_id: debug_id, purchase_id: purchase&.id)
      return redirect_to(account_path(tab: "refunded"), alert: "Refund failed (#{e.class}: #{e.message}). [#{debug_id}]")
    end

    redirect_to(account_path(tab: "refunded"), notice: "Refund complete.")
  end

  private

  def ensure_logged_in
    redirect_to root_path, alert: "Please log in to view your account." unless current_user
  end

  def table_exists?(model)
    return false unless model
    return false unless model.respond_to?(:table_name)

    ActiveRecord::Base.connection.data_source_exists?(model.table_name)
  rescue
    false
  end

  def col_exists?(model, col)
    return false unless model && col.present?
    return false unless table_exists?(model)

    ActiveRecord::Base.connection.column_exists?(model.table_name, col.to_s)
  rescue
    false
  end

  def user_funds_cents(user)
    if user.respond_to?(:balance_cents)
      user.balance_cents.to_i
    elsif user.respond_to?(:funds_cents)
      user.funds_cents.to_i
    elsif user.respond_to?(:balance)
      (BigDecimal(user.balance.to_s) * 100).to_i
    elsif user.respond_to?(:funds)
      (BigDecimal(user.funds.to_s) * 100).to_i
    else
      0
    end
  rescue
    0
  end

  def update_user_funds_cents!(user, cents)
    cents = cents.to_i

    if user.respond_to?(:balance_cents=)
      user.update!(balance_cents: cents)
    elsif user.respond_to?(:funds_cents=)
      user.update!(funds_cents: cents)
    elsif user.respond_to?(:balance=)
      user.update!(balance: cents / 100.0)
    elsif user.respond_to?(:funds=)
      user.update!(funds: cents / 100.0)
    else
      raise "no_funds_column"
    end
  end

  def purchase_total_cents(p)
    cols = p.class.column_names rescue []

    if cols.include?("total_cents") && p.respond_to?(:total_cents) && p.total_cents.to_i > 0
      p.total_cents.to_i
    elsif cols.include?("total_price_cents") && p.respond_to?(:total_price_cents) && p.total_price_cents.to_i > 0
      p.total_price_cents.to_i
    elsif cols.include?("unit_price_cents") && cols.include?("quantity") && p.respond_to?(:unit_price_cents) && p.respond_to?(:quantity)
      p.unit_price_cents.to_i * p.quantity.to_i
    elsif cols.include?("price_cents") && cols.include?("quantity") && p.respond_to?(:price_cents) && p.respond_to?(:quantity)
      p.price_cents.to_i * p.quantity.to_i
    else
      0
    end
  rescue
    0
  end

  def resolve_listing_for_purchase(p)
    return nil unless defined?(MarketplaceListing)

    cols = p.class.column_names rescue []

    if cols.include?("marketplace_listing_id") && p.respond_to?(:marketplace_listing_id) && p.marketplace_listing_id.present?
      MarketplaceListing.find_by(id: p.marketplace_listing_id)
    elsif cols.include?("listing_id") && p.respond_to?(:listing_id) && p.listing_id.present?
      MarketplaceListing.find_by(id: p.listing_id)
    else
      nil
    end
  rescue
    nil
  end

  def refunded_purchase?(p)
    cols = p.class.column_names rescue []

    if cols.include?("refunded") && p.respond_to?(:refunded)
      return !!p.refunded
    end

    if cols.include?("refunded_at") && p.respond_to?(:refunded_at)
      return p.refunded_at.present?
    end

    if cols.include?("status") && p.respond_to?(:status)
      return p.status.to_s == "refunded"
    end

    if cols.include?("debug_context") && p.respond_to?(:debug_context)
      h = parse_debug_context(p.debug_context)
      return true if h["refunded"] == true
      return true if h["status"].to_s == "refunded"
      return true if h["refund_status"].to_s == "refunded"

      if h["refund"].is_a?(Hash)
        r = h["refund"]
        return true if r["refunded"] == true
        return true if r["status"].to_s == "refunded"
        return true if r["refund_status"].to_s == "refunded"
        return true if r["refunded_at"].present?
        return true if r["at"].present?
      end

      return true if h["refunded_at"].present?
      return true if h["refund_at"].present?
    end

    false
  rescue
    false
  end

  def persist_refund!(p, debug_id:, note:, amount_cents:)
    cols = p.class.column_names rescue []
    now = Time.current
    attrs = {}

    attrs["refunded"] = true if cols.include?("refunded")
    attrs["refunded_at"] = now if cols.include?("refunded_at")
    attrs["status"] = "refunded" if cols.include?("status")
    attrs["refund_note"] = note if cols.include?("refund_note") && note.present?
    attrs["seller_note"] = note if cols.include?("seller_note") && note.present?
    attrs["note"] = note if cols.include?("note") && note.present?
    attrs["notes"] = note if cols.include?("notes") && note.present?
    attrs["refund_debug_id"] = debug_id if cols.include?("refund_debug_id")
    attrs["debug_id"] = debug_id if cols.include?("debug_id")

    if cols.include?("debug_context")
      h = parse_debug_context(p.debug_context)
      h["status"] = "refunded"
      h["refunded"] = true
      h["refunded_at"] = now.iso8601
      h["refund_note"] = note.to_s if note.present?
      h["refund_debug_id"] = debug_id
      h["refund_amount_cents"] = amount_cents.to_i
      h["refund"] ||= {}

      if h["refund"].is_a?(Hash)
        h["refund"]["status"] = "refunded"
        h["refund"]["refunded"] = true
        h["refund"]["refunded_at"] = now.iso8601
        h["refund"]["note"] = note.to_s if note.present?
        h["refund"]["debug_id"] = debug_id
        h["refund"]["amount_cents"] = amount_cents.to_i
      end

      attrs["debug_context"] = h.to_json
    end

    p.update!(attrs) if attrs.any?

    fresh = p.class.find_by(id: p.id)
    ok = fresh && refunded_purchase?(fresh)
    snapshot_refund_state(tag: ok ? "persist_ok" : "refund_not_persisted", debug_id: debug_id, purchase_id: p.id, total_cents: amount_cents, purchase: fresh)
    ok
  rescue => e
    Rails.logger.error("REFUND_PERSIST_FAILED [#{debug_id}] #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
    snapshot_refund_state(tag: "persist_exception", debug_id: debug_id, purchase_id: p&.id, total_cents: amount_cents, purchase: p)
    false
  end

  def snapshot_refund_state(tag:, debug_id:, purchase_id:, total_cents: nil, purchase: nil)
    return unless defined?(Rails) && Rails.respond_to?(:logger)

    p = purchase || (defined?(MarketplacePurchase) ? MarketplacePurchase.find_by(id: purchase_id) : nil)
    l = p ? resolve_listing_for_purchase(p) : nil

    sample_cols = p ? (p.class.column_names rescue []) : []
    snapshot = {}

    if p
      %w[id seller_id buyer_id marketplace_listing_id listing_id quantity unit_price_cents total_price_cents total_cents price_cents status refunded refunded_at debug_id debug_context refund_note seller_note note notes set_slug set_name era route_type condition].each do |key|
        next unless sample_cols.include?(key)

        snapshot[key] = (p.public_send(key) rescue nil)
      end
    end

    linfo = {}

    if l
      lcols = l.class.column_names rescue []

      %w[id seller_id status quantity price_cents set_slug set_name route_type product_type_name condition].each do |key|
        next unless lcols.include?(key)

        linfo[key] = (l.public_send(key) rescue nil)
      end
    end

    Rails.logger.error("REFUND_SNAPSHOT [#{debug_id}] tag=#{tag} purchase_id=#{purchase_id} total_cents=#{total_cents}")
    Rails.logger.error("REFUND_SNAPSHOT [#{debug_id}] purchase_cols_present=#{sample_cols.join(",")}") if sample_cols.any?
    Rails.logger.error("REFUND_SNAPSHOT [#{debug_id}] purchase_values=#{snapshot.inspect}") if snapshot.any?
    Rails.logger.error("REFUND_SNAPSHOT [#{debug_id}] listing_values=#{linfo.inspect}") if linfo.any?
  rescue
  end

  def parse_debug_context(raw)
    return {} if raw.nil?

    s = raw.to_s.strip
    return {} if s.blank?

    begin
      v = JSON.parse(s)
      return v.is_a?(Hash) ? v : {}
    rescue
    end

    begin
      v = YAML.safe_load(s, permitted_classes: [ Time, Date ], aliases: true)
      return v.is_a?(Hash) ? v : {}
    rescue
    end

    if s.start_with?("{") && s.include?("=>")
      s2 = s.dup
      s2.gsub!(/:(\w+)\s*=>/, '"\1"=>')
      s2.gsub!("=>", ":")
      s2.gsub!(/\bnil\b/, "null")

      begin
        v = JSON.parse(s2)
        return v.is_a?(Hash) ? v : {}
      rescue
      end
    end

    {}
  rescue
    {}
  end

  def purchase_address_hash(p)
    cols = p.class.column_names rescue []

    pick = lambda do |names|
      names.each do |name|
        next unless cols.include?(name)

        value = p.public_send(name) rescue nil
        return value.to_s if value.present?
      end
      ""
    end

    {
      name: pick.call(%w[shipping_name address_name name]),
      line1: pick.call(%w[address_line1 shipping_line1 line1 addr1 address1]),
      line2: pick.call(%w[address_line2 shipping_line2 line2 addr2 address2]),
      city: pick.call(%w[address_city shipping_city city town]),
      county: pick.call(%w[address_county shipping_county county state]),
      postcode: pick.call(%w[address_postcode shipping_postcode postcode eircode zip]),
      country_code: pick.call(%w[address_country_code shipping_country_code country_code])
    }
  rescue
    { name: "", line1: "", line2: "", city: "", county: "", postcode: "", country_code: "" }
  end
end
