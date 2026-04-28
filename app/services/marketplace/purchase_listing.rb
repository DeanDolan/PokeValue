module Marketplace
  class PurchaseListing
    class PurchaseError < StandardError; end

    FUNDS_KEYS = %i[funds_cents balance_cents wallet_cents funds balance wallet].freeze
    PRICE_KEYS = %i[price_cents unit_price_cents price unit_price].freeze
    QTY_KEYS   = %i[available_quantity quantity qty stock].freeze
    SOLD_KEYS  = %i[sold_quantity purchased_quantity].freeze
    STATUS_KEYS = %i[status state].freeze

    def self.call!(listing_id:, buyer:, quantity:)
      debug_id = SecureRandom.hex(6)
      raise PurchaseError, "buyer required" if buyer.nil?

      qty = quantity.to_i
      qty = 1 if qty <= 0

      ActiveRecord::Base.transaction do
        listing = MarketplaceListing.lock.find(listing_id)

        seller = begin
          if listing.respond_to?(:user) && listing.user.present?
            listing.user
          elsif listing.respond_to?(:seller) && listing.seller.present?
            listing.seller
          else
            User.find(listing.user_id)
          end
        end

        buyer = User.lock.find(buyer.id)
        seller = User.lock.find(seller.id)

        if buyer.id == seller.id
          raise PurchaseError, "cannot buy your own listing (listing_id=#{listing.id}, buyer_id=#{buyer.id})"
        end

        status = read_status(listing)
        if status && status.to_s.downcase != "active"
          raise PurchaseError, "listing not active (status=#{status.inspect}, listing_id=#{listing.id})"
        end

        unit_price_cents = read_money_cents(listing, PRICE_KEYS)
        raise PurchaseError, "listing price missing (listing_id=#{listing.id})" if unit_price_cents.nil? || unit_price_cents <= 0

        available = read_available_units(listing)
        raise PurchaseError, "listing has no available quantity (listing_id=#{listing.id})" if available <= 0
        if qty > available
          raise PurchaseError, "quantity exceeds available (requested=#{qty}, available=#{available}, listing_id=#{listing.id})"
        end

        total_cents = unit_price_cents * qty

        buyer_funds_cents = read_money_cents(buyer, FUNDS_KEYS)
        raise PurchaseError, "buyer funds missing (buyer_id=#{buyer.id})" if buyer_funds_cents.nil?
        if buyer_funds_cents < total_cents
          raise PurchaseError, "insufficient funds (buyer_funds=#{buyer_funds_cents}c, needed=#{total_cents}c, buyer_id=#{buyer.id}, listing_id=#{listing.id})"
        end

        holding = nil
        holding_id = listing.respond_to?(:holding_id) ? listing.holding_id : nil
        if holding_id.present? && defined?(Holding)
          holding = Holding.lock.find_by(id: holding_id)
          if holding.nil?
            raise PurchaseError, "holding missing for listing (holding_id=#{holding_id}, listing_id=#{listing.id})"
          end
          if holding.respond_to?(:user_id) && holding.user_id.to_i != seller.id
            raise PurchaseError, "holding does not belong to seller (holding_id=#{holding.id}, seller_id=#{seller.id}, holding_user_id=#{holding.user_id})"
          end
          if holding.respond_to?(:quantity)
            if holding.quantity.to_i < qty
              raise PurchaseError, "seller holding insufficient at purchase (holding_qty=#{holding.quantity}, requested=#{qty}, holding_id=#{holding.id}, listing_id=#{listing.id})"
            end
          end
        end

        write_money_cents!(buyer, FUNDS_KEYS, buyer_funds_cents - total_cents)

        seller_funds_cents = read_money_cents(seller, FUNDS_KEYS)
        raise PurchaseError, "seller funds missing (seller_id=#{seller.id})" if seller_funds_cents.nil?
        write_money_cents!(seller, FUNDS_KEYS, seller_funds_cents + total_cents)

        seller_cost_per_unit_cents = nil
        realised_pl_cents = nil

        if holding
          if holding.respond_to?(:cost_per_unit)
            seller_cost_per_unit_cents = (BigDecimal(holding.cost_per_unit.to_s) * 100).to_i
            realised_pl_cents = (unit_price_cents - seller_cost_per_unit_cents) * qty
          end

          if holding.respond_to?(:quantity=)
            holding.quantity = holding.quantity.to_i - qty
            holding.save!
          end
        end

        apply_listing_decrement!(listing, qty)

        listing_era = listing.respond_to?(:era) ? listing.era.to_s : ""
        listing_set_name = listing.respond_to?(:set_name) ? listing.set_name.to_s : ""
        listing_set_slug = listing.respond_to?(:set_slug) ? listing.set_slug.to_s : ""
        listing_route_type = listing.respond_to?(:route_type) ? listing.route_type.to_s : ""
        listing_product_name =
          if listing.respond_to?(:product_name) && listing.product_name.present?
            listing.product_name.to_s
          elsif listing.respond_to?(:product_type) && listing.product_type.present?
            listing.product_type.to_s
          else
            ""
          end
        listing_condition = listing.respond_to?(:condition) ? listing.condition.to_s : ""

        purchase = MarketplacePurchase.create!(
          buyer_id: buyer.id,
          seller_id: seller.id,
          marketplace_listing_id: listing.id,
          holding_id: holding&.id,
          set_slug: listing_set_slug,
          route_type: listing_route_type,
          product_name: listing_product_name,
          era: listing_era,
          set_name: listing_set_name,
          condition: listing_condition,
          quantity: qty,
          unit_price_cents: unit_price_cents,
          total_price_cents: total_cents,
          seller_cost_per_unit_cents: seller_cost_per_unit_cents,
          realised_pl_cents: realised_pl_cents,
          debug_id: debug_id,
          debug_context: build_debug_context(
            listing: listing,
            buyer: buyer,
            seller: seller,
            qty: qty,
            unit_price_cents: unit_price_cents,
            total_cents: total_cents,
            available: available,
            buyer_funds_cents: buyer_funds_cents,
            seller_funds_cents: seller_funds_cents
          )
        )

        purchase
      end
    rescue => e
      Rails.logger.error("PURCHASE_FAILED [#{debug_id}] #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
      raise PurchaseError, "[#{debug_id}] #{e.message}"
    end

    def self.build_debug_context(listing:, buyer:, seller:, qty:, unit_price_cents:, total_cents:, available:, buyer_funds_cents:, seller_funds_cents:)
      {
        listing_id: listing.id,
        buyer_id: buyer.id,
        seller_id: seller.id,
        requested_qty: qty,
        unit_price_cents: unit_price_cents,
        total_cents: total_cents,
        listing_available_before: available,
        listing_status: read_status(listing),
        buyer_funds_before_cents: buyer_funds_cents,
        seller_funds_before_cents: seller_funds_cents,
        listing_attrs: safe_attrs(listing),
        buyer_attrs: safe_attrs(buyer, keys: FUNDS_KEYS),
        seller_attrs: safe_attrs(seller, keys: FUNDS_KEYS)
      }.to_json
    rescue
      ""
    end

    def self.safe_attrs(obj, keys: nil)
      h = obj.respond_to?(:attributes) ? obj.attributes : {}
      if keys
        out = {}
        keys.each do |k|
          ks = k.to_s
          out[ks] = h[ks] if h.key?(ks)
        end
        out
      else
        h.slice("id", "user_id", "seller_id", "holding_id", "status", "state", "quantity", "available_quantity", "sold_quantity", "purchased_quantity", "price", "price_cents", "unit_price", "unit_price_cents")
      end
    rescue
      {}
    end

    def self.read_status(listing)
      STATUS_KEYS.each do |k|
        return listing.public_send(k) if listing.respond_to?(k) && listing.public_send(k).present?
      end
      nil
    end

    def self.read_available_units(listing)
      sold = 0
      SOLD_KEYS.each do |k|
        if listing.respond_to?(k) && listing.public_send(k).present?
          sold = listing.public_send(k).to_i
          break
        end
      end

      if listing.respond_to?(:available_quantity) && listing.available_quantity.present?
        return listing.available_quantity.to_i
      end

      QTY_KEYS.each do |k|
        if listing.respond_to?(k) && listing.public_send(k).present?
          total = listing.public_send(k).to_i
          return [ total - sold, 0 ].max
        end
      end

      0
    end

    def self.apply_listing_decrement!(listing, qty)
      if listing.respond_to?(:available_quantity) && !listing.available_quantity.nil?
        listing.available_quantity = listing.available_quantity.to_i - qty
        listing.available_quantity = 0 if listing.available_quantity.to_i < 0
        listing.save!
        return
      end

      SOLD_KEYS.each do |k|
        if listing.respond_to?(k) && !listing.public_send(k).nil?
          listing.public_send("#{k}=", listing.public_send(k).to_i + qty)
          listing.save!
          return
        end
      end

      if listing.respond_to?(:quantity) && !listing.quantity.nil?
        listing.quantity = listing.quantity.to_i - qty
        listing.quantity = 0 if listing.quantity.to_i < 0
        listing.save!
        return
      end

      raise PurchaseError, "cannot decrement listing inventory (listing_id=#{listing.id})"
    end

    def self.read_money_cents(obj, keys)
      attrs = obj.respond_to?(:attributes) ? obj.attributes : {}

      keys.each do |k|
        ks = k.to_s
        next unless attrs.key?(ks) || obj.respond_to?(k)

        v = obj.respond_to?(k) ? obj.public_send(k) : attrs[ks]
        next if v.nil?

        if ks.end_with?("_cents")
          return v.to_i
        else
          return (BigDecimal(v.to_s) * 100).to_i
        end
      end

      nil
    rescue
      nil
    end

    def self.write_money_cents!(obj, keys, new_cents)
      attrs = obj.respond_to?(:attributes) ? obj.attributes : {}

      keys.each do |k|
        ks = k.to_s
        next unless attrs.key?(ks) || obj.respond_to?(k)

        if ks.end_with?("_cents")
          obj.public_send("#{k}=", new_cents.to_i)
          obj.save!
          return
        else
          obj.public_send("#{k}=", BigDecimal(new_cents.to_i) / 100)
          obj.save!
          return
        end
      end

      raise PurchaseError, "no writable funds column found on #{obj.class.name}"
    end
  end
end
