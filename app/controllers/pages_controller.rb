class PagesController < ApplicationController
  require "json"
  require "date"

  PRODUCT_TYPE_NAMES = {
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

  CONDITION_OPTIONS = [
    "Mint Sealed",
    "Loosely Sealed",
    "Mini Tear/Hole (<2cm)",
    "Unsealed",
    "Small Tear (>2cm)",
    "Big Tear (>1 inch)",
    "Small Imperfections",
    "Big Imperfections",
    "Pressure Marks",
    "Slightly Dented",
    "Heavy Dented",
    "Damaged",
    "Box Only",
    "Contents Only"
  ].freeze

  def auction
  end

  def community
    @community_channels = CommunityPost::CHANNELS.map { |channel| [ CommunityPost.channel_label(channel), channel ] }
    requested_channel = params[:channel].to_s
    @selected_channel = CommunityPost::CHANNELS.include?(requested_channel) ? requested_channel : CommunityPost::CHANNELS.first
    @community_post = CommunityPost.new(channel: @selected_channel)
    @community_posts = CommunityPost.includes(:user, :community_reactions, { community_comments: :user }, { images_attachments: :blob }).where(channel: @selected_channel).order(created_at: :desc)
  end

  def product
    set = find_set!(params[:slug])
    product = find_product_in_set!(set, params[:type])

    @set_slug = set["slug"].to_s
    @set_name = set["name"].to_s
    @era = set["era"].to_s
    @release_date = display_date(set["releaseDate"])
    @set_logo_url = set_logo_url(set)

    @product_name = product["name"].to_s
    @product_type = product["type"].to_s
    @product_type_name = PRODUCT_TYPE_NAMES[normalize_type(@product_type)] || @product_name
    @product_img_url = sealed_image_url(@set_name, product)

    @current_route_type = params[:type].to_s
    @watchlist_sku = "#{@set_slug}:#{@current_route_type}"
    @admin_value_sku = value_override_sku(@set_slug, @current_route_type)

    override = product_value_override(@set_slug, @current_route_type, @product_type, @product_name)
    @product_value = override&.value || product["value"] || 0

    @marketplace_listing_quantity = marketplace_listing_count
    @is_watchlisted = product_watchlisted?
    @holdings = matching_holdings
    @holdings_qty = @holdings.sum { |holding| holding.quantity.to_i }
    @condition_options = CONDITION_OPTIONS
  end

  def search_index
    q = params[:q].to_s.strip
    return render json: { sets: [], products: [] } if q.blank?

    tokens = q.downcase.split(/\s+/)
    sets = []
    products = []

    sets_data.values.each do |set|
      set_name = set["name"].to_s
      era = set["era"].to_s
      slug = set["slug"].to_s

      if matches_tokens?("#{set_name} #{era}", tokens)
        sets << {
          kind: "set",
          label: set_name,
          subtitle: "Set · #{era}",
          image_url: set_search_image_url(set),
          href: set_path(slug: slug),
          era: era
        }
      end

      sealed_products(set).each do |product|
        name = product["name"].to_s
        type = product["type"].to_s
        label = name.presence || PRODUCT_TYPE_NAMES[normalize_type(type)] || type

        next unless matches_tokens?("#{set_name} #{era} #{label} #{type}", tokens)

        products << {
          kind: "product",
          label: label,
          subtitle: "Product · #{set_name}",
          image_url: sealed_image_url(set_name, product),
          href: set_product_path(slug: slug, type: route_type_for_product(type, name)),
          set_name: set_name
        }
      end
    end

    render json: { sets: sets.first(25), products: products.first(50) }
  end

  private

  # Loads all set and sealed product data from config/sets.json.
  def sets_data
    @sets_data ||= JSON.parse(File.read(Rails.root.join("config", "sets.json"), encoding: "bom|utf-8"))
  end

  # Finds one set by slug or returns a normal Rails not-found page.
  def find_set!(slug)
    set = sets_data.values.find { |item| item["slug"].to_s == slug.to_s }
    raise ActiveRecord::RecordNotFound unless set

    set
  end

  # Returns the list of sealed products for one set.
  def sealed_products(set)
    Array(set["products"] || set["sealed"] || [])
  end

  # Finds the exact product requested by the route type.
  def find_product_in_set!(set, route_type)
    parsed = parse_route_type(route_type)

    product = sealed_products(set).find do |item|
      type = item["type"].to_s
      name = item["name"].to_s

      next false unless normalize_type(type) == parsed[:base_type]

      product_slug_matches = parsed[:product_slug].blank? || slugify(name) == parsed[:product_slug]
      variant_slug_matches = parsed[:variant_slug].blank? || slugify(extract_variant(name)) == parsed[:variant_slug]
      origin_slug_matches = parsed[:origin_slug].blank? || slugify(infer_origin(type, name)) == parsed[:origin_slug]

      product_slug_matches && variant_slug_matches && origin_slug_matches
    end

    raise ActiveRecord::RecordNotFound unless product

    product
  end

  # Uses the set box image for the main sets grid.
  def set_card_image_url(set)
    asset_from_folder("sets", set["boxImage"])
  end

  # Uses logo first for search, then box art, then the app logo.
  def set_search_image_url(set)
    logo = file_in_folder("sets", set["logo"])
    return safe_asset_path("sets/#{logo}") if logo

    set_card_image_url(set)
  end

  # Uses the set logo image at the top of set and product pages.
  def set_logo_url(set)
    override = set_logo_override(set["slug"])
    return safe_asset_path("sets/#{override}") if override && file_in_folder("sets", override)

    asset_from_folder("sets", set["logo"])
  end

  # Uses a sealed product image, including known filename overrides.
  def sealed_image_url(set_name, product)
    override = sealed_image_override(set_name, product["type"])
    return safe_asset_path("sealed/#{override}") if override && file_in_folder("sealed", override)

    asset_from_folder("sealed", product["img"])
  end

  # Finds an image inside app/assets/images without causing Propshaft missing-asset errors.
  def asset_from_folder(folder, source)
    file = file_in_folder(folder, source)
    return safe_asset_path("#{folder}/#{file}") if file

    safe_asset_path("pokevaluelogo.png")
  end

  # Looks for exact filename matches first, then case-insensitive matches.
  def file_in_folder(folder, source)
    file = File.basename(source.to_s)
    return nil if file.blank?

    path = Rails.root.join("app", "assets", "images", folder)
    exact = path.join(file)
    return file if File.file?(exact)

    files = asset_files(folder)
    files.find { |name| name.downcase == file.downcase }
  rescue
    nil
  end

  # Caches folder filenames during one request so repeated image checks stay simple.
  def asset_files(folder)
    @asset_files ||= {}
    @asset_files[folder] ||= Dir.children(Rails.root.join("app", "assets", "images", folder))
  rescue
    []
  end

  # Returns an asset URL, falling back to the PokeValue logo if the requested asset is missing.
  def safe_asset_path(path)
    view_context.asset_path(path)
  rescue
    begin
      view_context.asset_path("pokevaluelogo.png")
    rescue
      "/assets/pokevaluelogo.png"
    end
  end

  # Handles the one set logo that has used more than one filename.
  def set_logo_override(slug)
    return "celebrationsclassiccollection.png" if normalize_text(slug) == "celebrationsclassiccollection"

    nil
  end

  # Handles older image names that differ from the JSON value.
  def sealed_image_override(set_name, type)
    return nil unless normalize_text(set_name) == "scarlet & violet base"

    case normalize_type(type)
    when "booster_box"
      "scarletandviolet_boosterbox.png"
    when "booster_bundle"
      "scarletandviolet_boosterbundle.png"
    end
  end

  # Formats product release dates as YYYY-MM-DD when possible.
  def display_date(value)
    date = parse_date(value)
    date ? date.strftime("%Y-%m-%d") : value.to_s.presence || "TBD"
  end

  # Safely parses loose date strings from config/sets.json.
  def parse_date(value)
    Date.parse(value.to_s)
  rescue
    nil
  end

  # Builds route types that can handle duplicate product types like multiple ETBs.
  def route_type_for_product(type, name)
    base = normalize_type(type)
    variant = extract_variant(name)
    origin = infer_origin(type, name)

    route = base.dup
    route << "--v-#{slugify(variant)}" if variant.present?
    route << "--o-#{slugify(origin)}" if origin.present?
    route << "--p-#{slugify(name)}" if PRODUCT_SLUG_TYPES.include?(base) && name.present?
    route
  end

  # Reads the base type, variant, origin and product slug from a product route.
  def parse_route_type(route_type)
    parts = route_type.to_s.strip.split("--")
    parsed = {
      base_type: normalize_type(parts.shift),
      variant_slug: nil,
      origin_slug: nil,
      product_slug: nil
    }

    parts.each do |part|
      parsed[:variant_slug] = part.delete_prefix("v-") if part.start_with?("v-")
      parsed[:origin_slug] = part.delete_prefix("o-") if part.start_with?("o-")
      parsed[:product_slug] = part.delete_prefix("p-") if part.start_with?("p-")
    end

    parsed
  end

  # Pulls the text inside brackets from product names like Elite Trainer Box (Lucario).
  def extract_variant(name)
    name.to_s[/\(([^)]+)\)/, 1].to_s.strip.presence
  end

  # Detects Pokemon Center products.
  def infer_origin(type, name)
    return "Pokemon Center" if normalize_type(type) == "pc_etb"
    return "Pokemon Center" if normalize_text(name).include?("pokemon center")

    nil
  end

  # Normalises text for matching and searching.
  def normalize_text(value)
    value.to_s.unicode_normalize(:nfkc).downcase.strip.gsub(/\s+/, " ")
  end

  # Normalises product type codes used in routes and JSON.
  def normalize_type(value)
    value.to_s.strip.downcase.tr("-", "_").gsub(/\s+/, "_")
  end

  # Converts text into a safe route slug.
  def slugify(value)
    normalize_text(value).gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
  end

  # Checks if every search token appears in the text.
  def matches_tokens?(text, tokens)
    haystack = text.to_s.downcase
    tokens.all? { |token| haystack.include?(token) }
  end

  # Builds the same admin product-value SKU used by product value forms.
  def value_override_sku(set_slug, route_type)
    clean_set = set_slug.to_s.strip.gsub(/[^a-zA-Z0-9\-_]+/, "-").gsub(/\A-+|-+\z/, "")
    clean_type = route_type.to_s.strip.gsub(/[^a-zA-Z0-9\-_]+/, "-").gsub(/\A-+|-+\z/, "")

    "#{clean_set}--#{clean_type}"
  end

  # Finds any admin-edited value for this product.
  def product_value_override(set_slug, route_type, product_type, product_name)
    return nil unless defined?(Product)

    candidates = [
      value_override_sku(set_slug, route_type),
      "#{set_slug}:#{route_type}"
    ]

    base_type = normalize_type(product_type)

    unless PRODUCT_SLUG_TYPES.include?(base_type) && route_type.to_s.include?("--p-")
      candidates << value_override_sku(set_slug, base_type)
      candidates << "#{set_slug}:#{base_type}"
    end

    product = Product.where(sku: candidates.uniq).order(updated_at: :desc).first
    return product if product

    return nil unless Product.column_names.include?("set_name") && Product.column_names.include?("name")

    Product.where(set_name: @set_name.to_s, name: product_name.to_s).order(updated_at: :desc).first
  rescue
    nil
  end

  # Counts active marketplace listings for the selected product.
  def marketplace_listing_count
    return 0 unless defined?(MarketplaceListing)

    scopes = [
      MarketplaceListing.active.where(set_slug: @set_slug, route_type: @current_route_type),
      MarketplaceListing.active.where(product_sku: "#{@set_slug}:#{@current_route_type}"),
      MarketplaceListing.active.where(product_sku: "#{@set_slug}--#{@current_route_type}"),
      MarketplaceListing.active.where(set_slug: @set_slug, product_type_name: @product_name),
      MarketplaceListing.active.where(set_slug: @set_slug, product_type_name: @product_type_name)
    ]

    scopes.each do |scope|
      quantity = scope.sum(:quantity).to_i
      return quantity if quantity.positive?
    end

    0
  rescue
    0
  end

  # Checks if this product is already saved to the current user's watchlist.
  def product_watchlisted?
    user_signed_in? && current_user.watchlists.exists?(product_sku: @watchlist_sku)
  rescue
    false
  end

  # Finds the current user's matching holdings for the selected product.
  def matching_holdings
    return [] unless user_signed_in?

    current_user.holdings.where(set_name: @set_name).order(created_at: :desc).select do |holding|
      holding_name = normalize_text(holding.product_type)
      product_name = normalize_text(@product_name)
      type_name = normalize_text(@product_type_name)

      holding_name == product_name || (holding_name == type_name && same_image_file?(holding.image, @product_img_url))
    end
  rescue
    []
  end

  # Extracts only the image filename for image comparisons.
  def image_file_key(value)
    value.to_s.split("?").first.split("/").last.to_s.downcase.strip
  rescue
    ""
  end

  # Compares two image paths by filename.
  def same_image_file?(left, right)
    left_key = image_file_key(left)
    right_key = image_file_key(right)

    return false if left_key.blank? || right_key.blank?

    left_key == right_key ||
      left.to_s.downcase.include?(right_key) ||
      right.to_s.downcase.include?(left_key)
  rescue
    false
  end
end
