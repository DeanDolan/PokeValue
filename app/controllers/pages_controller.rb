class PagesController < ApplicationController
  require "json"
  require "date"

  # Maps product type codes from sets.json into readable names for the views.
  PRODUCT_TYPE_NAMES = {
    "etb"                      => "Elite Trainer Box",
    "pc_etb"                   => "Pokemon Center Elite Trainer Box",
    "booster_box"              => "Booster Box",
    "half_booster_box"         => "Half Booster Box",
    "booster_pack"             => "Booster Pack",
    "booster_bundle"           => "Booster Bundle",
    "booster_bundle_display"   => "Booster Bundle Display",
    "enhanced_booster_box"     => "Enhanced Booster Box",
    "ultra_premium_collection" => "Ultra Premium Collection",
    "upc"                      => "Ultra Premium Collection",
    "spc"                      => "Super Premium Collection",
    "collection_box"           => "Collection Box",
    "tin"                      => "Tin",
    "mini_tin"                 => "Mini Tin",
    "mini_tin_display"         => "Mini Tin Display",
    "blister_pack"             => "Blister Pack",
    "blister_pack_display"     => "Blister Pack Display"
  }

  def home; end
  def marketplace; end
  def auction; end
  def raffle; end

  # Loads community posts for the selected channel.
  def community
    @community_channels = CommunityPost::CHANNELS.map { |channel| [ CommunityPost.channel_label(channel), channel ] }
    requested_channel = params[:channel].to_s
    @selected_channel = CommunityPost::CHANNELS.include?(requested_channel) ? requested_channel : CommunityPost::CHANNELS.first
    @community_post = CommunityPost.new(channel: @selected_channel)
    @community_posts = CommunityPost.includes(:user, :community_reactions, { community_comments: :user }, { images_attachments: :blob }).where(channel: @selected_channel).order(created_at: :desc)
  end

  # Redirects the old showcase route to the community page.
  def showcase
    redirect_to community_path
  end

  # Loads the full set list and prepares set images for the sets page.
  def sets
    data        = load_sets_data
    images_sets = Rails.root.join("app", "assets", "images", "sets")

    @eras = [ "Mega Evolution", "Scarlet & Violet", "Sword & Shield" ]

    @era_badges = {
      "Mega Evolution"   => safe_asset_path("sets/megaevolution.png"),
      "Scarlet & Violet" => safe_asset_path("sets/scarletandviolet.png"),
      "Sword & Shield"   => safe_asset_path("sets/swordandshield.png")
    }

    @sets = data.values.map do |s|
      box = File.basename(s["boxImage"].to_s) rescue nil
      img =
        if box.present? && File.exist?(images_sets.join(box))
          safe_asset_path("sets/#{box}")
        else
          safe_asset_path("pokevaluelogo.png")
        end

      { name: s["name"], era: s["era"], image_url: img, slug: s["slug"] }
    end
  end

  # Loads one set page, including set metadata, urgency status, and sealed products.
  def set
    slug = params[:slug].to_s
    data = load_sets_data

    s = data.values.find { |x| x["slug"].to_s == slug }
    raise ActiveRecord::RecordNotFound unless s

    images_sets   = Rails.root.join("app", "assets", "images", "sets")
    images_sealed = Rails.root.join("app", "assets", "images", "sealed")

    @set_slug     = slug
    @set_name     = s["name"]
    @era          = s["era"]
    raw_release   = s["releaseDate"]
    @release_date = raw_release
    @total_value  = s["totalValue"]
    @total_cards  = s["totalCards"]
    @cards        = s["cards"]
    @secret       = s["secretCards"]

    # Applies admin overrides for set statistics where the override table exists.
    begin
      if defined?(SetOverride)
        cols = SetOverride.column_names rescue []
        ov =
          if cols.include?("set_slug")
            SetOverride.find_by(set_slug: slug)
          elsif cols.include?("slug")
            SetOverride.find_by(slug: slug)
          else
            nil
          end

        if ov
          @total_value = ov.total_value if ov.respond_to?(:total_value) && ov.total_value.present?
          @total_cards = ov.total_cards if ov.respond_to?(:total_cards) && ov.total_cards.present?
          @cards       = ov.cards if ov.respond_to?(:cards) && ov.cards.present?
          @secret      = ov.secret_cards if ov.respond_to?(:secret_cards) && ov.secret_cards.present?
        end
      end
    rescue
    end

    # Uses an override logo first, then the JSON logo, then the app fallback logo.
    logo_override = set_logo_override_filename(slug: slug)
    logo_base = File.basename(s["logo"].to_s) rescue nil
    @logo_url =
      if logo_override.present? && File.exist?(images_sets.join(logo_override))
        safe_asset_path("sets/#{logo_override}")
      elsif logo_base.present? && File.exist?(images_sets.join(logo_base))
        safe_asset_path("sets/#{logo_base}")
      else
        safe_asset_path("pokevaluelogo.png")
      end

    release_date_obj =
      begin
        raw_release.present? ? Date.parse(raw_release.to_s) : nil
      rescue ArgumentError
        nil
      end

    @urgency_label = "Unknown"
    @urgency_class = "urgency-unknown"

    # Calculates how close the set is to likely out-of-print status based on release age.
    if release_date_obj
      today  = Date.current
      months = (today.year - release_date_obj.year) * 12 + (today.month - release_date_obj.month)

      if months < 6
        @urgency_label = "Very Low (0–6 months)"
        @urgency_class = "urgency-green"
      elsif months < 12
        @urgency_label = "Low (6–12 months)"
        @urgency_class = "urgency-yellow"
      elsif months < 18
        @urgency_label = "Medium (12–18 months)"
        @urgency_class = "urgency-orange"
      elsif months < 24
        @urgency_label = "High (18–24 months)"
        @urgency_class = "urgency-red"
      elsif months < 36
        @urgency_label = "Very High (2–3 years)"
        @urgency_class = "urgency-brown"
      else
        @urgency_label = "Out Of Print (>3 years)"
        @urgency_class = "urgency-black"
      end
    end

    sealed_files = begin
      Dir.children(images_sealed)
    rescue
      []
    end

    products_src = s["products"] || s["sealed"] || []
    @products =
      Array(products_src).filter_map do |prod|
        next if hidden_product?(slug: slug, product: prod)

        img_key  = prod["img"]  || prod[:img]
        name_key = prod["name"] || prod[:name]
        type_key = (prod["type"] || prod[:type]).to_s

        # Chooses the correct sealed image while falling back safely if the image is missing.
        override = sealed_override_filename(set_name: @set_name, type_key: type_key)
        img_url =
          if override.present? && File.exist?(images_sealed.join(override))
            safe_asset_path("sealed/#{override}")
          else
            requested_img = img_key.to_s
            img_base = begin
              File.basename(requested_img)
            rescue
              ""
            end

            actual_img = nil
            if img_base.present?
              down = img_base.downcase
              actual_img = sealed_files.find { |f| f.downcase == down }
            end

            if actual_img.present?
              safe_asset_path("sealed/#{actual_img}")
            else
              safe_asset_path("pokevaluelogo.png")
            end
          end

        # Builds the route type so variants, duplicate product types and Pokemon Center products have unique URLs.
        route_type = build_route_type_for_product(type_key: type_key, name: name_key.to_s)

        {
          type:    type_key,
          name:    name_key.to_s,
          img_url: img_url,
          link:    set_product_path(slug: slug, type: route_type)
        }
      end
  end

  # Loads an individual sealed product page.
  def product
    slug      = params[:slug].to_s
    want_type = params[:type].to_s

    data = load_sets_data
    s = data.values.find { |x| x["slug"].to_s == slug }
    raise ActiveRecord::RecordNotFound unless s

    products_src = s["products"] || s["sealed"] || []

    # Splits the route type into base type, variant, origin and exact product slug.
    parsed = parse_route_type(want_type)
    base_type = parsed[:base_type]
    want_variant_slug = parsed[:variant_slug]
    want_origin_slug = parsed[:origin_slug]
    want_product_slug = parsed[:product_slug]

    # Finds the exact product from the set JSON using type, product slug, variant and origin.
    p =
      Array(products_src).find do |prod|
        next if hidden_product?(slug: slug, product: prod)

        prod_type = (prod["type"] || prod[:type]).to_s
        next false unless normalize_type(prod_type) == base_type

        prod_name = (prod["name"] || prod[:name]).to_s
        v = extract_variant(prod_name)
        o = infer_origin(type_key: prod_type, name: prod_name)

        v_slug = v.present? ? slugify(v) : nil
        o_slug = o.present? ? slugify(o) : nil
        p_slug = slugify(prod_name)

        ok_product = want_product_slug.present? ? (p_slug == want_product_slug) : true
        ok_variant = want_variant_slug.present? ? (v_slug == want_variant_slug) : true
        ok_origin  = want_origin_slug.present?  ? (o_slug == want_origin_slug)  : true

        ok_product && ok_variant && ok_origin
      end

    raise ActiveRecord::RecordNotFound unless p

    images_sets   = Rails.root.join("app", "assets", "images", "sets")
    images_sealed = Rails.root.join("app", "assets", "images", "sealed")

    sealed_files = begin
      Dir.children(images_sealed)
    rescue
      []
    end

    @set_slug = slug
    @set_name = s["name"]

    raw_release = s["releaseDate"].to_s.presence
    release_date_obj =
      if raw_release
        begin
          Date.parse(raw_release)
        rescue ArgumentError
          nil
        end
      else
        nil
      end

    @release_date = release_date_obj ? release_date_obj.strftime("%Y-%m-%d") : (raw_release || "TBD")
    @era          = s["era"].to_s

    # Loads the set logo for the product page.
    set_logo_override = set_logo_override_filename(slug: slug)
    set_logo_base = File.basename(s["logo"].to_s) rescue nil
    @set_logo_url =
      if set_logo_override.present? && File.exist?(images_sets.join(set_logo_override))
        safe_asset_path("sets/#{set_logo_override}")
      elsif set_logo_base.present? && File.exist?(images_sets.join(set_logo_base))
        safe_asset_path("sets/#{set_logo_base}")
      else
        safe_asset_path("pokevaluelogo.png")
      end

    @product_name      = (p["name"] || p[:name]).to_s
    @product_type      = (p["type"] || p[:type]).to_s

    # Loads the product image from app/assets/images/sealed, with override support.
    override = sealed_override_filename(set_name: @set_name, type_key: @product_type)
    if override.present? && File.exist?(images_sealed.join(override))
      @product_img_url = safe_asset_path("sealed/#{override}")
    else
      requested_img = (p["img"] || p[:img]).to_s
      img_base = begin
        File.basename(requested_img)
      rescue
        ""
      end

      actual_img = nil
      if img_base.present?
        down = img_base.downcase
        actual_img = sealed_files.find { |f| f.downcase == down }
      end

      @product_img_url =
        if actual_img.present?
          safe_asset_path("sealed/#{actual_img}")
        else
          safe_asset_path("pokevaluelogo.png")
        end
    end

    @product_type_name = PRODUCT_TYPE_NAMES[normalize_type(@product_type)] || @product_name
    fallback_value     = p["value"]    || p[:value]
    @product_listings  = p["listings"] || p[:listings]

    # Uses a Product row as the admin-editable value override for this product.
    @admin_value_sku = build_value_override_sku(set_slug: slug, route_type: want_type)
    override_row = find_product_value_override(set_slug: slug, route_type: want_type, product_type: @product_type, product_name: @product_name)
    @product_value = override_row&.value || fallback_value

    @urgency_label = "Unknown"
    @urgency_class = "urgency-unknown"

    # Reuses the same urgency calculation used on the set page.
    if release_date_obj
      today  = Date.current
      months = (today.year - release_date_obj.year) * 12 + (today.month - release_date_obj.month)

      if months < 6
        @urgency_label = "Very Low (0–6 months)"
        @urgency_class = "urgency-green"
      elsif months < 12
        @urgency_label = "Low (6–12 months)"
        @urgency_class = "urgency-yellow"
      elsif months < 18
        @urgency_label = "Medium (12–18 months)"
        @urgency_class = "urgency-orange"
      elsif months < 24
        @urgency_label = "High (18–24 months)"
        @urgency_class = "urgency-red"
      elsif months < 36
        @urgency_label = "Very High (2–3 years)"
        @urgency_class = "urgency-brown"
      else
        @urgency_label = "Out Of Print (>3 years)"
        @urgency_class = "urgency-black"
      end
    end

    @eras = [ "Mega Evolution", "Scarlet & Violet", "Sword & Shield" ]
    @types = [
      "Booster Box", "Half Booster Box", "Booster Pack",
      "Elite Trainer Box", "Pokemon Center Elite Trainer Box",
      "Booster Bundle", "Booster Bundle Display",
      "Ultra Premium Collection", "Super Premium Collection",
      "Collection Box", "Tin", "Mini Tin", "Mini Tin Display",
      "Blister Pack", "Blister Pack Display"
    ]
    @conditions = [
      "Mint Sealed", "Loosely Sealed", "Unsealed",
      "Big Tear", "Small Tear", "Big Imperfections", "Small Imperfections",
      "Pressure Marks", "Slightly Dented", "Heavy Dented", "Damaged",
      "Box Only", "Contents Only"
    ]

    # Shows the logged-in user's matching holdings under the product page.
    @holdings =
      if defined?(current_user) && current_user
        current_user.holdings.where(set_name: @set_name).order(created_at: :desc).select do |holding|
          holding_name = normalize_text(holding.product_type)
          exact_name = normalize_text(@product_name)
          type_name = normalize_text(@product_type_name)

          holding_name == exact_name ||
            (holding_name == type_name && same_image_file?(holding.image, @product_img_url))
        end
      else
        []
      end
  end

  # Returns JSON search results for the navbar/global search.
  def search_index
    q = params[:q].to_s.strip
    return render json: { sets: [], products: [] } if q.blank?

    tokens        = q.downcase.split(/\s+/)
    data          = load_sets_data
    images_sets   = Rails.root.join("app", "assets", "images", "sets")
    images_sealed = Rails.root.join("app", "assets", "images", "sealed")

    sealed_files = begin
      Dir.children(images_sealed)
    rescue
      []
    end

    sets     = []
    products = []

    data.values.each do |s|
      set_name = s["name"].to_s
      era      = s["era"].to_s
      slug     = s["slug"].to_s

      # Picks the best available image for each set search result.
      logo_base = File.basename(s["logo"].to_s) rescue nil
      box_base  = File.basename(s["boxImage"].to_s) rescue nil
      set_img =
        if logo_base.present? && File.exist?(images_sets.join(logo_base))
          safe_asset_path("sets/#{logo_base}")
        elsif box_base.present? && File.exist?(images_sets.join(box_base))
          safe_asset_path("sets/#{box_base}")
        else
          safe_asset_path("pokevaluelogo.png")
        end

      hay_set     = "#{set_name} #{era}".downcase
      set_matches = tokens.all? { |t| hay_set.include?(t) }

      if set_matches
        sets << {
          kind:      "set",
          label:     set_name,
          subtitle:  "Set · #{era}",
          image_url: set_img,
          href:      set_path(slug: slug),
          era:       era
        }
      end

      Array(s["products"] || s["sealed"]).each do |prod|
        next if hidden_product?(slug: slug, product: prod)

        type_code = (prod["type"] || prod[:type]).to_s
        prod_name = (prod["name"] || prod[:name]).to_s
        friendly  = prod_name.presence || PRODUCT_TYPE_NAMES[normalize_type(type_code)] || type_code

        # Picks the best available image for each product search result.
        override = sealed_override_filename(set_name: set_name, type_key: type_code)
        prod_img =
          if override.present? && File.exist?(images_sealed.join(override))
            safe_asset_path("sealed/#{override}")
          else
            requested_img = (prod["img"] || prod[:img]).to_s
            img_base = begin
              File.basename(requested_img)
            rescue
              ""
            end

            actual_img = nil
            if img_base.present?
              down = img_base.downcase
              actual_img = sealed_files.find { |f| f.downcase == down }
            end

            if actual_img.present?
              safe_asset_path("sealed/#{actual_img}")
            else
              safe_asset_path("pokevaluelogo.png")
            end
          end

        route_type = build_route_type_for_product(type_key: type_code, name: prod_name)

        hay_prod     = "#{set_name} #{era} #{friendly} #{type_code} #{prod_name}".downcase
        prod_matches = tokens.all? { |t| hay_prod.include?(t) }

        if prod_matches
          products << {
            kind:      "product",
            label:     friendly,
            subtitle:  "Product · #{set_name}",
            image_url: prod_img,
            href:      set_product_path(slug: slug, type: route_type),
            set_name:  set_name
          }
        end
      end
    end

    render json: { sets: sets.first(25), products: products.first(50) }
  end

  private

  # Returns a safe asset URL and falls back to the app logo if the requested file cannot be found.
  def safe_asset_path(path, fallback = "pokevaluelogo.png")
    begin
      view_context.asset_path(path)
    rescue
      begin
        view_context.asset_path(fallback)
      rescue
        "/assets/#{fallback}"
      end
    end
  end

  # Loads set data from config/sets.json and merges in manual sets and products that are not in the JSON file yet.
  def load_sets_data
    path = Rails.root.join("config", "sets.json")
    data = JSON.parse(File.read(path, encoding: "bom|utf-8"))
    data = manual_extra_sets_data.merge(data)
    merge_manual_extra_products(data)
  end

  # Manually adds upcoming or custom sets before they are fully present in config/sets.json.
  def manual_extra_sets_data
    {
      "perfectorder" => {
        "slug" => "perfectorder",
        "name" => "Perfect Order",
        "era" => "Mega Evolution",
        "releaseDate" => "March 27 2026",
        "totalValue" => nil,
        "totalCards" => 203,
        "cards" => 203,
        "secretCards" => 0,
        "logo" => "images/sets/perfectorderlogo.png",
        "boxImage" => "images/sets/perfectorder.png",
        "pokedataUrl" => "https://www.pokedata.io/sets#ENGLISH",
        "sealed" => [
          {
            "type" => "etb",
            "name" => "Elite Trainer Box",
            "img" => "images/sealed/perfectorder_etb.png"
          },
          {
            "type" => "pc_etb",
            "name" => "Pokemon Center Elite Trainer Box",
            "img" => "images/sealed/perfectorder_pcetb.png"
          },
          {
            "type" => "booster_box",
            "name" => "Booster Box",
            "img" => "images/sealed/perfectorder_boosterbox.png"
          },
          {
            "type" => "booster_bundle",
            "name" => "Booster Bundle",
            "img" => "images/sealed/perfectorder_boosterbundle.png"
          }
        ]
      },
      "ascendedheroes" => {
        "slug" => "ascendedheroes",
        "name" => "Ascended Heroes",
        "era" => "Mega Evolution",
        "releaseDate" => "January 30 2026",
        "totalValue" => nil,
        "totalCards" => 615,
        "cards" => 615,
        "secretCards" => 0,
        "logo" => "images/sets/ascendedheroeslogo.png",
        "boxImage" => "images/sets/ascendedheroes.png",
        "pokedataUrl" => "https://www.pokedata.io/sets#ENGLISH",
        "sealed" => [
          {
            "type" => "etb",
            "name" => "Elite Trainer Box",
            "img" => "images/sealed/ascendedheroes_etb.png"
          },
          {
            "type" => "pc_etb",
            "name" => "Pokemon Center Elite Trainer Box",
            "img" => "images/sealed/ascendedheroes_pcetb.png"
          },
          {
            "type" => "booster_bundle",
            "name" => "Booster Bundle",
            "img" => "images/sealed/ascendedheroes_boosterbundle.png"
          }
        ]
      }
    }
  end

  # Manually adds sealed products to existing sets without needing to replace the full sets.json file.
  def merge_manual_extra_products(data)
    manual_extra_products_by_slug.each do |slug, products|
      target = data[slug.to_s] || data.values.find { |x| x["slug"].to_s == slug.to_s }
      next unless target

      key = target.key?("products") ? "products" : "sealed"
      target[key] = Array(target[key] || target["sealed"] || target["products"])

      products.each do |product|
        exists = target[key].any? do |existing|
          normalize_text(existing["name"] || existing[:name]) == normalize_text(product["name"]) &&
            normalize_type(existing["type"] || existing[:type]) == normalize_type(product["type"])
        end

        target[key] << product unless exists
      end
    end

    data
  end

  # Product additions requested for Phantasmal Flames, Destined Rivals, 151, Prismatic Evolutions and Ascended Heroes.
  def manual_extra_products_by_slug
    {
      "phantasmalflames" => [
        {
          "type" => "collection_box",
          "name" => "First Partner Illustration Collection Series 1",
          "img" => "images/sealed/phantasmalflames_firstpartnerseries1.png"
        },
        {
          "type" => "collection_box",
          "name" => "Pokémon Day 2026 Collection",
          "img" => "images/sealed/phantasmalflames_pokemonday2026collection.png"
        },
        {
          "type" => "tin",
          "name" => "Mega Charizard Y Ex Tin",
          "img" => "images/sealed/phantasmalflames_megacharizardyextin.png"
        },
        {
          "type" => "tin",
          "name" => "Mega Charizard X Ex Tin",
          "img" => "images/sealed/phantasmalflames_megacharizardxextin.png"
        }
      ],
      "destinedrivals" => [
        {
          "type" => "booster_pack",
          "name" => "Booster Pack",
          "img" => "images/sealed/destinedrivals_booster.png"
        },
        {
          "type" => "ultra_premium_collection",
          "name" => "Team Rocket's Moltres Ultra Premium Collection",
          "img" => "images/sealed/destinedrivals_teamrocketsmoltresultrapremiumcollection.png"
        },
        {
          "type" => "half_booster_box",
          "name" => "Half Booster Box (18 Packs)",
          "img" => "images/sealed/destinedrivals_halfboosterbox.png"
        }
      ],
      "151" => [
        {
          "type" => "mini_tin",
          "name" => "Mini Tin",
          "img" => "images/sealed/151_minitin.png"
        },
        {
          "type" => "mini_tin_display",
          "name" => "Mini Tin Display",
          "img" => "images/sealed/151_minitindisplay.png"
        }
      ],
      "prismaticevolutions" => [
        {
          "type" => "mini_tin",
          "name" => "Mini Tin",
          "img" => "images/sealed/prismaticevolutions_minitin.png"
        },
        {
          "type" => "mini_tin_display",
          "name" => "Mini Tin Display",
          "img" => "images/sealed/prismaticevolutions_minitindisplay.png"
        }
      ],
      "ascendedheroes" => [
        {
          "type" => "mini_tin",
          "name" => "Mini Tin",
          "img" => "images/sealed/ascendedheroes_minitin.png"
        },
        {
          "type" => "mini_tin_display",
          "name" => "Mini Tin Display",
          "img" => "images/sealed/ascendedheroes_minitindisplay.png"
        },
        {
          "type" => "collection_box",
          "name" => "Mega Feraligatr Ex Box",
          "img" => "images/sealed/ascendedheroes_megaferaligatrexbox.png"
        },
        {
          "type" => "collection_box",
          "name" => "Mega Meganium Ex Box",
          "img" => "images/sealed/ascendedheroes_megameganiumexbox.png"
        },
        {
          "type" => "collection_box",
          "name" => "Mega Emboar Ex Box",
          "img" => "images/sealed/ascendedheroes_megaemboarexbox.png"
        },
        {
          "type" => "collection_box",
          "name" => "First Partners Deluxe Pin Collection",
          "img" => "images/sealed/ascendedheroes_firstpartnersdeluxepincollection.png"
        },
        {
          "type" => "collection_box",
          "name" => "Mega Lucario Premium Poster Collection",
          "img" => "images/sealed/ascendedheroes_megalucariopremiumpostercollection.png"
        },
        {
          "type" => "collection_box",
          "name" => "Mega Gardevoir Premium Poster Collection",
          "img" => "images/sealed/ascendedheroes_megagardevoirpremiumpostercollection.png"
        },
        {
          "type" => "blister_pack",
          "name" => "Charmander Tech Sticker Collection",
          "img" => "images/sealed/ascendedheroes_charmandertechstickercollection.png"
        },
        {
          "type" => "blister_pack",
          "name" => "Gastly Tech Sticker Collection",
          "img" => "images/sealed/ascendedheroes_gastlytechstickercollection.png"
        },
        {
          "type" => "blister_pack",
          "name" => "Erika's Tangela 2-Pack Blister",
          "img" => "images/sealed/ascendedheroes_erikastangela2packblister.png"
        },
        {
          "type" => "blister_pack",
          "name" => "Larry's Komala 2-Pack Blister",
          "img" => "images/sealed/ascendedheroes_larryskomala2packblister.png"
        },
        {
          "type" => "blister_pack_display",
          "name" => "2-Pack Blister Display",
          "img" => "images/sealed/ascendedheroes2packblisterdisplay.png"
        },
        {
          "type" => "blister_pack_display",
          "name" => "Tech Sticker Collection Display",
          "img" => "images/sealed/ascendedheroes_techstickercollectiondisplay.png"
        }
      ]
    }
  end

  # Handles one-off set logo filename fixes.
  def set_logo_override_filename(slug:)
    s = normalize_text(slug)
    return "celebrationsclassiccollection.png" if s == "celebrationsclassiccollection"
    nil
  end

  # Handles one-off sealed product image filename fixes.
  def sealed_override_filename(set_name:, type_key:)
    sn = normalize_text(set_name)
    base = normalize_type(type_key)

    if sn == normalize_text("Scarlet & Violet Base")
      return "scarletandviolet_boosterbox.png" if base == "booster_box"
      return "scarletandviolet_boosterbundle.png" if base == "booster_bundle"
    end

    nil
  end

  # Hides products that should not be shown in the app.
  def hidden_product?(slug:, product:)
    false
  end

  # Normalises text for safer comparisons.
  def normalize_text(s)
    s.to_s.unicode_normalize(:nfkc).downcase.strip.gsub(/\s+/, " ")
  end

  # Normalises product type codes into the app's standard format.
  def normalize_type(t)
    x = t.to_s.strip.downcase
    x = x.tr("-", "_")
    x = x.gsub(/\s+/, "_")
    x
  end

  # Converts a name or variant into a URL-safe slug.
  def slugify(s)
    normalize_text(s).gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
  end

  # Extracts product variants such as Lucario from names like Elite Trainer Box (Lucario).
  def extract_variant(name)
    m = name.to_s.match(/\(([^)]+)\)/)
    m ? m[1].to_s.strip : nil
  end

  # Detects whether a product is a Pokemon Center version.
  def infer_origin(type_key:, name:)
    t = normalize_type(type_key)
    n = normalize_text(name)
    return "Pokemon Center" if t == "pc_etb"
    return "Pokemon Center" if n.include?("pokemon center")
    nil
  end

  # Checks whether a product type should include the product name in its route to avoid duplicate links.
  def route_needs_product_slug?(base)
    [
      "collection_box",
      "tin",
      "mini_tin",
      "mini_tin_display",
      "booster_pack",
      "blister_pack",
      "blister_pack_display",
      "half_booster_box"
    ].include?(base.to_s)
  end

  # Builds unique route types for normal products, duplicate product types, variant products, and Pokemon Center products.
  def build_route_type_for_product(type_key:, name:)
    base   = normalize_type(type_key)
    variant = extract_variant(name)
    origin  = infer_origin(type_key: type_key, name: name)

    out = base.dup
    out << "--v-#{slugify(variant)}" if variant.present?
    out << "--o-#{slugify(origin)}"  if origin.present?
    out << "--p-#{slugify(name)}" if route_needs_product_slug?(base) && name.to_s.present?
    out
  end

  # Parses a route type back into its base type, variant slug, origin slug and product slug.
  def parse_route_type(route_type)
    raw = route_type.to_s.strip
    parts = raw.split("--")

    base = normalize_type(parts.shift || "")
    v = nil
    o = nil
    p = nil

    parts.each do |part|
      if part.start_with?("v-")
        v = part.delete_prefix("v-").to_s.strip
      elsif part.start_with?("o-")
        o = part.delete_prefix("o-").to_s.strip
      elsif part.start_with?("p-")
        p = part.delete_prefix("p-").to_s.strip
      end
    end

    { base_type: base, variant_slug: v.presence, origin_slug: o.presence, product_slug: p.presence }
  end

  # Creates a safe SKU key for admin product value overrides.
  def build_value_override_sku(set_slug:, route_type:)
    a = set_slug.to_s.strip.gsub(/[^a-zA-Z0-9\-_]+/, "-").gsub(/\A-+|-+\z/, "")
    b = route_type.to_s.strip.gsub(/[^a-zA-Z0-9\-_]+/, "-").gsub(/\A-+|-+\z/, "")
    "#{a}--#{b}"
  end

  # Finds a product value override using the current SKU first, then older SKU formats.
  def find_product_value_override(set_slug:, route_type:, product_type:, product_name:)
    return nil unless defined?(Product)

    candidates = []
    candidates << build_value_override_sku(set_slug: set_slug, route_type: route_type)
    candidates << "#{set_slug}:#{route_type}"

    unless route_needs_product_slug?(normalize_type(product_type)) && route_type.to_s.include?("--p-")
      candidates << build_value_override_sku(set_slug: set_slug, route_type: normalize_type(product_type))
      candidates << "#{set_slug}:#{normalize_type(product_type)}"
    end

    candidates.map(&:to_s).uniq.each do |sku|
      product = Product.find_by(sku: sku)
      return product if product.present?
    end

    if Product.column_names.include?("set_name") && Product.column_names.include?("name")
      product = Product.where(set_name: @set_name.to_s, name: product_name.to_s).order(updated_at: :desc).first
      return product if product.present?
    end

    nil
  rescue
    nil
  end

  def image_file_key(value)
    value.to_s.split("?").first.split("/").last.to_s.downcase.strip
  rescue
    ""
  end

  def same_image_file?(a, b)
    aa = a.to_s
    bb = b.to_s
    a_key = image_file_key(aa)
    b_key = image_file_key(bb)

    return false if a_key.blank? || b_key.blank?

    a_key == b_key || aa.downcase.include?(b_key) || bb.downcase.include?(a_key)
  rescue
    false
  end
end
