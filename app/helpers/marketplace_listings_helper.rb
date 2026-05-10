module MarketplaceListingsHelper
  MARKETPLACE_TYPE_MAP = {
    "etb" => "Elite Trainer Box",
    "pc_etb" => "Pokemon Center Elite Trainer Box",
    "booster_box" => "Booster Box",
    "half_booster_box" => "Half Booster Box",
    "booster_pack" => "Booster Pack",
    "booster_bundle" => "Booster Bundle",
    "booster_bundle_display" => "Booster Bundle Display",
    "enhanced_booster_box" => "Enhanced Booster Box",
    "ultra_premium_collection" => "Ultra Premium Collection",
    "upc" => "Ultra Premium Collection",
    "spc" => "Super Premium Collection",
    "collection_box" => "Collection Box",
    "tin" => "Tin",
    "mini_tin" => "Mini Tin",
    "mini_tin_display" => "Mini Tin Display",
    "blister_pack" => "Blister Pack",
    "blister_pack_display" => "Blister Pack Display"
  }.freeze

  PRODUCT_SLUG_TYPES = [
    "collection_box",
    "tin",
    "mini_tin",
    "mini_tin_display",
    "booster_pack",
    "blister_pack",
    "blister_pack_display",
    "half_booster_box"
  ].freeze

  # Product type labels used by marketplace filters and display rows.
  def marketplace_type_map
    MARKETPLACE_TYPE_MAP
  end

  # Conditions used by the marketplace forms.
  def marketplace_condition_options
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

  # EU country options used by the location filter.
  def marketplace_country_options
    if defined?(CountriesHelper::COUNTRIES)
      CountriesHelper::COUNTRIES
    else
      eu_countries.map { |country| [ country[:name], country[:code] ] }
    end
  end

  # Reads the set catalogue for marketplace views.
  def marketplace_sets_data
    @marketplace_sets_data ||= JSON.parse(File.read(Rails.root.join("config", "sets.json"), encoding: "bom|utf-8"))
  rescue
    {}
  end

  # Builds catalogue data used by the create-listing dropdowns.
  def marketplace_catalogue
    marketplace_sets_data.values.map do |set|
      {
        slug: set["slug"].to_s,
        name: set["name"].to_s,
        era: set["era"].to_s,
        products: Array(set["products"] || set["sealed"]).map do |product|
          {
            name: product["name"].to_s,
            type: product["type"].to_s,
            route_type: marketplace_route_type(product["type"], product["name"])
          }
        end
      }
    end
  end

  # Finds one set by slug.
  def marketplace_set(slug)
    marketplace_sets_data[slug.to_s] || marketplace_sets_data.values.find { |set| set["slug"].to_s == slug.to_s }
  end

  # Finds the era for one set slug.
  def marketplace_era(slug)
    marketplace_set(slug)&.dig("era").to_s
  end

  # Builds a product route type that can handle variants and duplicate product types.
  def marketplace_route_type(type, name)
    base = marketplace_normalize_type(type)
    route = base.dup
    variant = marketplace_variant(name)
    origin = marketplace_origin(type, name)

    route << "--v-#{marketplace_slug(variant)}" if variant.present?
    route << "--o-#{marketplace_slug(origin)}" if origin.present?
    route << "--p-#{marketplace_slug(name)}" if PRODUCT_SLUG_TYPES.include?(base) && name.to_s.present?
    route
  end

  # Displays the product type/name for a listing or sold row.
  def marketplace_display_product(record)
    return "-" unless record

    if record.respond_to?(:product_type_name) && record.product_type_name.present?
      return record.product_type_name.to_s
    end

    if record.respond_to?(:product_name) && record.product_name.present?
      return record.product_name.to_s
    end

    route_type = record.respond_to?(:route_type) ? record.route_type.to_s : ""
    base, variant = marketplace_split_route(route_type)
    base_name = MARKETPLACE_TYPE_MAP[base] || marketplace_titleize(base)

    variant.present? ? "#{base_name} (#{variant})" : base_name
  end

  # Splits route types such as etb--v-lucario into base type and variant text.
  def marketplace_split_route(route_type)
    parts = route_type.to_s.split("--")
    base = parts.shift.to_s
    variant = ""

    parts.each do |part|
      variant = marketplace_titleize(part.delete_prefix("v-")) if part.start_with?("v-")
    end

    [ base, variant ]
  end

  # Gets uploaded listing images.
  def marketplace_listing_images(listing)
    return [] unless listing.respond_to?(:photos) && listing.photos.attached?

    listing.photos.to_a.first(4)
  end

  # Shows stars from an average review score.
  def marketplace_stars(avg)
    value = avg.to_f.clamp(0.0, 5.0)
    rounded = ((value * 2).round / 2.0)
    full = rounded.floor
    half = (rounded - full) >= 0.5

    html = +""
    full.times { html << '<span class="pv-rating-star">★</span>' }
    html << '<span class="pv-rating-half">½</span>' if half
    %(<span class="pv-rating-stars">#{html}</span>).html_safe
  end

  # Badge images shown beside sellers.
  def marketplace_badges_for(user)
    badges = []
    badges << "badges/adminbadge.png" if user && user.respond_to?(:admin?) && user.admin?
    badges
  rescue
    []
  end

  # Human label for an offer status.
  def marketplace_offer_status_label(status)
    {
      "pending" => "Pending",
      "accepted" => "Accepted",
      "paid" => "Payment Sent",
      "confirmed_paid" => "Confirmed Paid",
      "rejected" => "Rejected",
      "cancelled" => "Cancelled"
    }[status.to_s] || marketplace_titleize(status)
  end

  # CSS class for offer status badges.
  def marketplace_offer_status_class(status)
    {
      "pending" => "ml-offer-pending",
      "accepted" => "ml-offer-accepted",
      "paid" => "ml-offer-paid",
      "confirmed_paid" => "ml-offer-confirmed",
      "rejected" => "ml-offer-rejected",
      "cancelled" => "ml-offer-rejected"
    }[status.to_s] || "ml-offer-pending"
  end

  # Finds seller display name.
  def marketplace_seller_name(user, fallback_id = nil)
    return user.username.to_s if user && user.respond_to?(:username) && user.username.present?

    "User ##{fallback_id}"
  end

  # Builds metadata for one holding in the create-listing dropdown.
  def marketplace_holding_option(holding)
    product = holding.product
    sku = product&.sku.to_s
    set_slug = sku.include?(":") ? sku.split(":", 2).first : ""
    set = marketplace_set(set_slug)

    {
      id: holding.id,
      label: [
        set&.dig("era").presence || holding.era,
        set&.dig("name").presence || holding.set_name,
        holding.product_type
      ].compact.join(" · "),
      available: holding.quantity.to_i - holding.listed_quantity.to_i,
      image: holding.image.presence || asset_path("pokevaluelogo.png")
    }
  end

  # Returns the listing linked to a sold purchase row.
  def marketplace_sold_listing(row, listing_map)
    return row if row.is_a?(MarketplaceListing)
    return listing_map[row.marketplace_listing_id.to_i] if row.respond_to?(:marketplace_listing_id) && row.marketplace_listing_id.present?

    nil
  end

  # Returns seller ID for sold rows.
  def marketplace_sold_seller_id(row, listing_map)
    return row.seller_id if row.respond_to?(:seller_id) && row.seller_id.present?

    marketplace_sold_listing(row, listing_map)&.seller_id
  end

  # Returns seller object for sold rows.
  def marketplace_sold_seller(row, listing_map)
    seller_id = marketplace_sold_seller_id(row, listing_map)
    seller_id.present? ? User.find_by(id: seller_id) : nil
  end

  # Returns set slug for sold rows.
  def marketplace_sold_set_slug(row, listing_map)
    return row.set_slug.to_s if row.respond_to?(:set_slug) && row.set_slug.present?

    marketplace_sold_listing(row, listing_map)&.set_slug.to_s
  end

  # Returns set name for sold rows.
  def marketplace_sold_set_name(row, listing_map)
    return row.set_name.to_s if row.respond_to?(:set_name) && row.set_name.present?

    marketplace_sold_listing(row, listing_map)&.set_name.to_s
  end

  # Returns country code for sold rows.
  def marketplace_sold_country(row, listing_map)
    return row.country_code.to_s if row.respond_to?(:country_code) && row.country_code.present?

    marketplace_sold_listing(row, listing_map)&.country_code.to_s
  end

  # Returns condition for sold rows.
  def marketplace_sold_condition(row, listing_map)
    return row.condition.to_s if row.respond_to?(:condition) && row.condition.present?

    marketplace_sold_listing(row, listing_map)&.condition.to_s
  end

  # Returns unit price cents for sold rows.
  def marketplace_sold_unit_cents(row, listing_map)
    return row.unit_price_cents.to_i if row.respond_to?(:unit_price_cents) && row.unit_price_cents.to_i > 0
    return row.price_cents.to_i if row.respond_to?(:price_cents) && row.price_cents.to_i > 0

    marketplace_sold_listing(row, listing_map)&.price_cents.to_i
  end

  # Returns sold quantity.
  def marketplace_sold_quantity(row, listing_map)
    return row.quantity.to_i if row.respond_to?(:quantity) && row.quantity.present?

    marketplace_sold_listing(row, listing_map)&.quantity.to_i
  end

  # Returns sold row date.
  def marketplace_sold_date(row, listing_map)
    row.created_at || marketplace_sold_listing(row, listing_map)&.updated_at
  end

  # Normalises product type codes.
  def marketplace_normalize_type(value)
    value.to_s.downcase.strip.tr("-", "_").gsub(/\s+/, "_")
  end

  # Converts text into title case.
  def marketplace_titleize(value)
    value.to_s.tr("_", " ").tr("-", " ").split.map(&:capitalize).join(" ")
  end

  # Converts text into route slug format.
  def marketplace_slug(value)
    value.to_s.unicode_normalize(:nfkc).downcase.strip.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
  end

  # Extracts text inside product-name brackets.
  def marketplace_variant(name)
    name.to_s[/\(([^)]+)\)/, 1].to_s.strip
  end

  # Detects Pokemon Center products.
  def marketplace_origin(type, name)
    return "Pokemon Center" if marketplace_normalize_type(type) == "pc_etb"
    return "Pokemon Center" if name.to_s.downcase.include?("pokemon center")

    ""
  end
end
