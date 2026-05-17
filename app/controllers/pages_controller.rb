class PagesController < ApplicationController
  require "json"

  # SHARED/_NAVBAR.HTML.ERB
  # Product types that need the product name added into the URL so navbar search links stay unique.
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

  # PAGES/AUCTION.HTML.ERB
  # Loads the main auction page from the Auction navbar link.
  def auction
  end

  # PAGES/COMMUNITY.HTML.ERB
  # Loads the community page, selected channel, new post form object and existing posts.
  def community
    @community_channels = CommunityPost::CHANNELS.map { |channel| [ CommunityPost.channel_label(channel), channel ] }
    requested_channel = params[:channel].to_s
    @selected_channel = CommunityPost::CHANNELS.include?(requested_channel) ? requested_channel : CommunityPost::CHANNELS.first
    @community_post = CommunityPost.new(channel: @selected_channel)
    @community_posts = CommunityPost.includes(:user, :community_reactions, { community_comments: :user }, { images_attachments: :blob }).where(channel: @selected_channel).order(created_at: :desc)
  end

  # SHARED/_NAVBAR.HTML.ERB
  # Searches config/sets.json and returns matching sets/products as JSON for the global navbar search.
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
        label = name

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

  # SHARED/_NAVBAR.HTML.ERB
  # Loads all set and sealed product data from config/sets.json for the navbar search.
  def sets_data
    @sets_data ||= JSON.parse(File.read(Rails.root.join("config", "sets.json"), encoding: "bom|utf-8"))
  end

  # SHARED/_NAVBAR.HTML.ERB
  # Returns the sealed products listed under one set in config/sets.json.
  def sealed_products(set)
    Array(set["sealed"] || [])
  end

  # SHARED/_NAVBAR.HTML.ERB
  # Gets the set box image used when a navbar search result needs set artwork.
  def set_card_image_url(set)
    asset_from_folder("sets", set["boxImage"])
  end

  # SHARED/_NAVBAR.HTML.ERB
  # Gets the best set image for navbar search results, using the logo first and box image second.
  def set_search_image_url(set)
    logo = file_in_folder("sets", set["logo"])
    return safe_asset_path("sets/#{logo}") if logo

    set_card_image_url(set)
  end

  # SHARED/_NAVBAR.HTML.ERB
  # Gets the sealed product image used in navbar product search results.
  def sealed_image_url(set_name, product)
    override = sealed_image_override(set_name, product["type"])
    return safe_asset_path("sealed/#{override}") if override && file_in_folder("sealed", override)

    asset_from_folder("sealed", product["img"])
  end

  # SHARED/_NAVBAR.HTML.ERB
  # Finds an image inside app/assets/images and falls back to the PokeValue logo if missing.
  def asset_from_folder(folder, source)
    file = file_in_folder(folder, source)
    return safe_asset_path("#{folder}/#{file}") if file

    safe_asset_path("pokevaluelogo.png")
  end

  # SHARED/_NAVBAR.HTML.ERB
  # Looks for an image file by exact filename first, then by case-insensitive filename.
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

  # SHARED/_NAVBAR.HTML.ERB
  # Caches image filenames from each image folder during the request.
  def asset_files(folder)
    @asset_files ||= {}
    @asset_files[folder] ||= Dir.children(Rails.root.join("app", "assets", "images", folder))
  rescue
    []
  end

  # SHARED/_NAVBAR.HTML.ERB
  # Builds a Rails asset path and falls back to the PokeValue logo if the asset cannot be found.
  def safe_asset_path(path)
    view_context.asset_path(path)
  rescue
    begin
      view_context.asset_path("pokevaluelogo.png")
    rescue
      "/assets/pokevaluelogo.png"
    end
  end

  # SHARED/_NAVBAR.HTML.ERB
  # Handles older Scarlet & Violet Base sealed image filenames that differ from config/sets.json.
  def sealed_image_override(set_name, type)
    return nil unless normalize_text(set_name) == "scarlet & violet base"

    case normalize_type(type)
    when "booster_box"
      "scarletandviolet_boosterbox.png"
    when "booster_bundle"
      "scarletandviolet_boosterbundle.png"
    end
  end

  # SHARED/_NAVBAR.HTML.ERB
  # Builds the product URL type used by navbar product search result links.
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

  # SHARED/_NAVBAR.HTML.ERB
  # Extracts the bracketed variant from product names like Elite Trainer Box (Lucario).
  def extract_variant(name)
    name.to_s[/\(([^)]+)\)/, 1].to_s.strip.presence
  end

  # SHARED/_NAVBAR.HTML.ERB
  # Checks whether a product is a Pokemon Center product for product URL building.
  def infer_origin(type, name)
    return "Pokemon Center" if normalize_type(type) == "pc_etb"
    return "Pokemon Center" if normalize_text(name).include?("pokemon center")

    nil
  end

  # SHARED/_NAVBAR.HTML.ERB
  # Normalises text so names, eras and product types can be compared consistently.
  def normalize_text(value)
    value.to_s.unicode_normalize(:nfkc).downcase.strip.gsub(/\s+/, " ")
  end

  # SHARED/_NAVBAR.HTML.ERB
  # Normalises product type codes from config/sets.json for product URL building.
  def normalize_type(value)
    value.to_s.strip.downcase.tr("-", "_").gsub(/\s+/, "_")
  end

  # SHARED/_NAVBAR.HTML.ERB
  # Converts text into a safe URL slug for product search result links.
  def slugify(value)
    normalize_text(value).gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
  end

  # SHARED/_NAVBAR.HTML.ERB
  # Checks that every search word typed by the user appears in the searchable text.
  def matches_tokens?(text, tokens)
    haystack = text.to_s.downcase
    tokens.all? { |token| haystack.include?(token) }
  end
end
