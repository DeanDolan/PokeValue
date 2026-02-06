class PagesController < ApplicationController
  require "json"

  PRODUCT_TYPE_NAMES = {
    "etb"                      => "Elite Trainer Box",
    "pc_etb"                   => "Pokemon Center Elite Trainer Box",
    "booster_box"              => "Booster Box",
    "booster_bundle"           => "Booster Bundle",
    "booster_bundle_display"   => "Booster Bundle Display",
    "enhanced_booster_box"     => "Enhanced Booster Box",
    "ultra_premium_collection" => "Ultra Premium Collection",
    "upc"                      => "Ultra Premium Collection",
    "spc"                      => "Super Premium Collection",
    "mini_tin"                 => "Mini Tin",
    "mini_tin_display"         => "Mini Tin Display"
  }

  def home; end
  def marketplace; end
  def auction; end
  def raffle; end
  def showcase; end

  def sets
    data        = load_sets_data
    images_sets = Rails.root.join("app", "assets", "images", "sets")

    @eras = [ "Mega Evolution", "Scarlet & Violet", "Sword & Shield" ]

    @era_badges = {
      "Mega Evolution"   => view_context.asset_path("sets/megaevolution.png"),
      "Scarlet & Violet" => view_context.asset_path("sets/scarletandviolet.png"),
      "Sword & Shield"   => view_context.asset_path("sets/swordandshield.png")
    }

    @sets = data.values.map do |s|
      box = File.basename(s["boxImage"].to_s) rescue nil
      img =
        if box.present? && File.exist?(images_sets.join(box))
          view_context.asset_path("sets/#{box}")
        else
          view_context.asset_path("pokevaluelogo.png")
        end

      { name: s["name"], era: s["era"], image_url: img, slug: s["slug"] }
    end
  end

  def set
    slug = params[:slug].to_s
    data = load_sets_data

    s = data.values.find { |x| x["slug"].to_s == slug }
    raise ActiveRecord::RecordNotFound unless s

    images_sets   = Rails.root.join("app", "assets", "images", "sets")
    images_sealed = Rails.root.join("app", "assets", "images", "sealed")

    @set_name     = s["name"]
    @era          = s["era"]
    raw_release   = s["releaseDate"]
    @release_date = raw_release
    @total_value  = s["totalValue"]
    @total_cards  = s["totalCards"]
    @cards        = s["cards"]
    @secret       = s["secretCards"]

    logo_override = set_logo_override_filename(slug: slug)
    logo_base = File.basename(s["logo"].to_s) rescue nil
    @logo_url =
      if logo_override.present? && File.exist?(images_sets.join(logo_override))
        view_context.asset_path("sets/#{logo_override}")
      elsif logo_base.present? && File.exist?(images_sets.join(logo_base))
        view_context.asset_path("sets/#{logo_base}")
      else
        view_context.asset_path("pokevaluelogo.png")
      end

    release_date_obj =
      begin
        raw_release.present? ? Date.parse(raw_release.to_s) : nil
      rescue ArgumentError
        nil
      end

    @urgency_label = "Unknown"
    @urgency_class = "urgency-unknown"

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

    products_src = s["products"] || s["sealed"] || []
    @products =
      Array(products_src).filter_map do |prod|
        next if hidden_product?(slug: slug, product: prod)

        img_key  = prod["img"]  || prod[:img]
        name_key = prod["name"] || prod[:name]
        type_key = (prod["type"] || prod[:type]).to_s

        override = sealed_override_filename(set_name: @set_name, type_key: type_key)
        if override.present? && File.exist?(images_sealed.join(override))
          img_url = view_context.asset_path("sealed/#{override}")
        else
          img_base = File.basename(img_key.to_s) rescue nil
          img_url =
            if img_base.present? && File.exist?(images_sealed.join(img_base))
              view_context.asset_path("sealed/#{img_base}")
            else
              view_context.asset_path("pokevaluelogo.png")
            end
        end

        route_type = build_route_type_for_product(type_key: type_key, name: name_key.to_s)

        {
          type:    type_key,
          name:    name_key.to_s,
          img_url: img_url,
          link:    set_product_path(slug: slug, type: route_type)
        }
      end
  end

  def product
    slug      = params[:slug].to_s
    want_type = params[:type].to_s

    data = load_sets_data
    s = data.values.find { |x| x["slug"].to_s == slug }
    raise ActiveRecord::RecordNotFound unless s

    products_src = s["products"] || s["sealed"] || []

    parsed = parse_route_type(want_type)
    base_type = parsed[:base_type]
    want_variant_slug = parsed[:variant_slug]
    want_origin_slug = parsed[:origin_slug]

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

        ok_variant = want_variant_slug.present? ? (v_slug == want_variant_slug) : true
        ok_origin  = want_origin_slug.present?  ? (o_slug == want_origin_slug)  : true

        ok_variant && ok_origin
      end

    raise ActiveRecord::RecordNotFound unless p

    images_sets   = Rails.root.join("app", "assets", "images", "sets")
    images_sealed = Rails.root.join("app", "assets", "images", "sealed")

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

    set_logo_override = set_logo_override_filename(slug: slug)
    set_logo_base = File.basename(s["logo"].to_s) rescue nil
    @set_logo_url =
      if set_logo_override.present? && File.exist?(images_sets.join(set_logo_override))
        view_context.asset_path("sets/#{set_logo_override}")
      elsif set_logo_base.present? && File.exist?(images_sets.join(set_logo_base))
        view_context.asset_path("sets/#{set_logo_base}")
      else
        view_context.asset_path("pokevaluelogo.png")
      end

    @product_name      = (p["name"] || p[:name]).to_s
    @product_type      = (p["type"] || p[:type]).to_s

    override = sealed_override_filename(set_name: @set_name, type_key: @product_type)
    if override.present? && File.exist?(images_sealed.join(override))
      @product_img_url = view_context.asset_path("sealed/#{override}")
    else
      img_base = File.basename((p["img"] || p[:img]).to_s) rescue nil
      @product_img_url =
        if img_base.present? && File.exist?(images_sealed.join(img_base))
          view_context.asset_path("sealed/#{img_base}")
        else
          view_context.asset_path("pokevaluelogo.png")
        end
    end

    @product_type_name = PRODUCT_TYPE_NAMES[normalize_type(@product_type)] || @product_name
    fallback_value     = p["value"]    || p[:value]
    @product_listings  = p["listings"] || p[:listings]

    @admin_value_sku = build_value_override_sku(set_slug: slug, route_type: want_type)
    override_row = Product.find_by(sku: @admin_value_sku)
    @product_value = override_row&.value || fallback_value

    @urgency_label = "Unknown"
    @urgency_class = "urgency-unknown"

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
      "Booster Box", "Elite Trainer Box", "Pokemon Center Elite Trainer Box",
      "Booster Bundle", "Booster Bundle Display",
      "Ultra Premium Collection", "Super Premium Collection",
      "Mini Tin", "Mini Tin Display"
    ]
    @conditions = [
      "Mint Sealed", "Loosely Sealed", "Unsealed",
      "Big Tear", "Small Tear",
      "Big Imperfections", "Small Imperfections",
      "Pressure Marks", "Slightly Dented", "Heavy Dented", "Damaged",
      "Box Only", "Contents Only"
    ]

    @holdings =
      if defined?(current_user) && current_user
        current_user.holdings.where(set_name: @set_name, product_type: @product_type_name).order(created_at: :desc)
      else
        []
      end
  end

  def search_index
    q = params[:q].to_s.strip
    return render json: { sets: [], products: [] } if q.blank?

    tokens        = q.downcase.split(/\s+/)
    data          = load_sets_data
    images_sets   = Rails.root.join("app", "assets", "images", "sets")
    images_sealed = Rails.root.join("app", "assets", "images", "sealed")

    sets     = []
    products = []

    data.values.each do |s|
      set_name = s["name"].to_s
      era      = s["era"].to_s
      slug     = s["slug"].to_s

      logo_base = File.basename(s["logo"].to_s) rescue nil
      box_base  = File.basename(s["boxImage"].to_s) rescue nil
      set_img =
        if logo_base.present? && File.exist?(images_sets.join(logo_base))
          view_context.asset_path("sets/#{logo_base}")
        elsif box_base.present? && File.exist?(images_sets.join(box_base))
          view_context.asset_path("sets/#{box_base}")
        else
          view_context.asset_path("pokevaluelogo.png")
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
        friendly  = PRODUCT_TYPE_NAMES[normalize_type(type_code)] || prod_name

        override = sealed_override_filename(set_name: set_name, type_key: type_code)
        if override.present? && File.exist?(images_sealed.join(override))
          prod_img = view_context.asset_path("sealed/#{override}")
        else
          img_base = File.basename((prod["img"] || prod[:img]).to_s) rescue nil
          prod_img =
            if img_base.present? && File.exist?(images_sealed.join(img_base))
              view_context.asset_path("sealed/#{img_base}")
            else
              view_context.asset_path("pokevaluelogo.png")
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

  def load_sets_data
    path = Rails.root.join("config", "sets.json")
    JSON.parse(File.read(path, encoding: "bom|utf-8"))
  end

  def set_logo_override_filename(slug:)
    s = normalize_text(slug)
    return "celebrationsclassiccollection.png" if s == "celebrationsclassiccollection"
    nil
  end

  def sealed_override_filename(set_name:, type_key:)
    sn = normalize_text(set_name)
    base = normalize_type(type_key)

    if sn == normalize_text("Scarlet & Violet Base")
      return "scarletandviolet_boosterbox.png" if base == "booster_box"
      return "scarletandviolet_boosterbundle.png" if base == "booster_bundle"
    end

    nil
  end

  def hidden_product?(slug:, product:)
    type_key = (product["type"] || product[:type]).to_s
    name_key = (product["name"] || product[:name]).to_s

    base_type = normalize_type(type_key)
    name_ci   = normalize_text(name_key)

    if normalize_text(slug) == "151"
      return true if [ "mini_tin", "mini_tin_display" ].include?(base_type)
    end

    hidden_names = [
      normalize_text("Team Rocket's Moltres ex Ultra Premium Collection")
    ]

    hidden_names.include?(name_ci)
  end

  def normalize_text(s)
    s.to_s.unicode_normalize(:nfkc).downcase.strip.gsub(/\s+/, " ")
  end

  def normalize_type(t)
    x = t.to_s.strip.downcase
    x = x.tr("-", "_")
    x = x.gsub(/\s+/, "_")
    x
  end

  def slugify(s)
    normalize_text(s).gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
  end

  def extract_variant(name)
    m = name.to_s.match(/\(([^)]+)\)/)
    m ? m[1].to_s.strip : nil
  end

  def infer_origin(type_key:, name:)
    t = normalize_type(type_key)
    n = normalize_text(name)
    return "Pokemon Center" if t == "pc_etb"
    return "Pokemon Center" if n.include?("pokemon center")
    nil
  end

  def build_route_type_for_product(type_key:, name:)
    base   = normalize_type(type_key)
    variant = extract_variant(name)
    origin  = infer_origin(type_key: type_key, name: name)

    out = base.dup
    out << "--v-#{slugify(variant)}" if variant.present?
    out << "--o-#{slugify(origin)}"  if origin.present?
    out
  end

  def parse_route_type(route_type)
    raw = route_type.to_s.strip
    parts = raw.split("--")

    base = normalize_type(parts.shift || "")
    v = nil
    o = nil

    parts.each do |p|
      if p.start_with?("v-")
        v = p.delete_prefix("v-").to_s.strip
      elsif p.start_with?("o-")
        o = p.delete_prefix("o-").to_s.strip
      end
    end

    { base_type: base, variant_slug: v.presence, origin_slug: o.presence }
  end

  def build_value_override_sku(set_slug:, route_type:)
    a = set_slug.to_s.strip.gsub(/[^a-zA-Z0-9\-_]+/, "-").gsub(/\A-+|-+\z/, "")
    b = route_type.to_s.strip.gsub(/[^a-zA-Z0-9\-_]+/, "-").gsub(/\A-+|-+\z/, "")
    "#{a}--#{b}"
  end
end
