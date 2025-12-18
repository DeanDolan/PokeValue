# References:
# - Rails controllers, params, rendering:
#   https://guides.rubyonrails.org/action_controller_overview.html
# - Active Record basics and querying:
#   https://guides.rubyonrails.org/active_record_basics.html
# - JSON parsing in Ruby:
#   https://ruby-doc.org/stdlib/libdoc/json/rdoc/JSON.html

class PagesController < ApplicationController
  require "json"

  # Central place for turning product type codes into friendly labels
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

  # Static pages that are layout only for now
  def home; end
  def marketplace; end
  def auction; end
  def raffle; end
  def showcase; end

  # Sets list page
  def sets
    data        = load_sets_data
    images_sets = Rails.root.join("app", "assets", "images", "sets")

    # Fixed list of eras I want to show in the sidebar
    @eras = [ "Mega Evolution", "Scarlet & Violet", "Sword & Shield" ]

    # Badge images per era for the header area
    @era_badges = {
      "Mega Evolution"   => view_context.asset_path("sets/megaevolution.png"),
      "Scarlet & Violet" => view_context.asset_path("sets/scarletandviolet.png"),
      "Sword & Shield"   => view_context.asset_path("sets/swordandshield.png")
    }

    # Build a plain Ruby hash per set that the view can loop over
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

  # Single set page
  def set
    slug = params[:slug].to_s
    data = load_sets_data

    # Find the entry in the JSON data that matches the slug
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

    # Try to resolve the set logo from the assets folder, fall back to app logo
    logo_base = File.basename(s["logo"].to_s) rescue nil
    @logo_url =
      if logo_base.present? && File.exist?(images_sets.join(logo_base))
        view_context.asset_path("sets/#{logo_base}")
      else
        view_context.asset_path("pokevaluelogo.png")
      end

    # --- Urgency for set-level box ---
    # Convert release date into a Date object so I can compare months since release
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
      # Approx months since release by comparing year and month
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
    # ---------------------------------

    # Some data files use "products", some "sealed" – I handle both
    products_src = s["products"] || s["sealed"] || []
    @products = Array(products_src).map do |p|
      img_key  = p["img"]  || p[:img]
      name_key = p["name"] || p[:name]
      type_key = (p["type"] || p[:type]).to_s

      img_base = File.basename(img_key.to_s) rescue nil
      img_url =
        if img_base.present? && File.exist?(images_sealed.join(img_base))
          view_context.asset_path("sealed/#{img_base}")
        else
          view_context.asset_path("pokevaluelogo.png")
        end

      {
        type:    type_key,
        name:    name_key.to_s,
        img_url: img_url,
        link:    product_path(slug: slug, type: type_key)
      }
    end
  end

  # Single product page
  def product
    slug      = params[:slug].to_s
    want_type = params[:type].to_s

    data = load_sets_data
    s = data.values.find { |x| x["slug"].to_s == slug }
    raise ActiveRecord::RecordNotFound unless s

    products_src = s["products"] || s["sealed"] || []

    # Find the product entry that matches the type in the URL
    p = Array(products_src).find { |prod| (prod["type"] || prod[:type]).to_s == want_type }
    raise ActiveRecord::RecordNotFound unless p

    images_sets   = Rails.root.join("app", "assets", "images", "sets")
    images_sealed = Rails.root.join("app", "assets", "images", "sealed")

    @set_slug = slug
    @set_name = s["name"]

    raw_release = s["releaseDate"].to_s.presence
    # Try to parse the date into a proper Date for formatting and urgency logic
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

    # Resolve set logo for the top right panel
    set_logo_base = File.basename(s["logo"].to_s) rescue nil
    @set_logo_url =
      if set_logo_base.present? && File.exist?(images_sets.join(set_logo_base))
        view_context.asset_path("sets/#{set_logo_base}")
      else
        view_context.asset_path("pokevaluelogo.png")
      end

    # Resolve the product image
    img_base = File.basename((p["img"] || p[:img]).to_s) rescue nil
    @product_img_url =
      if img_base.present? && File.exist?(images_sealed.join(img_base))
        view_context.asset_path("sealed/#{img_base}")
      else
        view_context.asset_path("pokevaluelogo.png")
      end

    @product_name      = (p["name"] || p[:name]).to_s
    @product_type      = (p["type"] || p[:type]).to_s
    # Prefer a friendly label from the mapping, fall back to the raw name
    @product_type_name = PRODUCT_TYPE_NAMES[@product_type] || @product_name
    @product_value     = p["value"]    || p[:value]
    @product_listings  = p["listings"] || p[:listings]

    # Urgency Level for product page (same logic as set)
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

    # Static lists the view uses to show context, filters or dropdowns
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

    # If user is logged in, show their past holdings for this product
    @holdings =
      if defined?(current_user) && current_user
        current_user.holdings.where(set_name: @set_name, product_type: @product_type_name).order(created_at: :desc)
      else
        []
      end
  end

  # JSON endpoint for the global search bar
  def search_index
    q = params[:q].to_s.strip
    return render json: { sets: [], products: [] } if q.blank?

    # Split the query into lowercase tokens for flexible matching
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

      # Try set logo first, fall back to box image, then app logo
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

      # Go through each sealed product for this set and see if it matches the query
      Array(s["products"] || s["sealed"]).each do |p|
        type_code = (p["type"] || p[:type]).to_s
        friendly  = PRODUCT_TYPE_NAMES[type_code] || (p["name"] || p[:name]).to_s
        prod_name = (p["name"] || p[:name]).to_s

        img_base = File.basename((p["img"] || p[:img]).to_s) rescue nil
        prod_img =
          if img_base.present? && File.exist?(images_sealed.join(img_base))
            view_context.asset_path("sealed/#{img_base}")
          else
            view_context.asset_path("pokevaluelogo.png")
          end

        hay_prod     = "#{set_name} #{era} #{friendly} #{type_code} #{prod_name}".downcase
        prod_matches = tokens.all? { |t| hay_prod.include?(t) }

        if prod_matches
          products << {
            kind:      "product",
            label:     friendly,
            subtitle:  "Product · #{set_name}",
            image_url: prod_img,
            href:      product_path(slug: slug, type: type_code),
            set_name:  set_name
          }
        end
      end
    end

    # Keep response size under control so global search stays snappy
    render json: { sets: sets.first(25), products: products.first(50) }
  end

  private

  # Helper for loading and parsing the sets JSON once per request
  def load_sets_data
    path = Rails.root.join("config", "sets.json")
    JSON.parse(File.read(path, encoding: "bom|utf-8"))
  end
end
