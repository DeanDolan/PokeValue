require "json" # Allows this controller to work with JSON catalogue data
require "date" # Allows this controller to parse and sort release dates

module Admin # Groups this controller inside the admin namespace
  class ProductsController < BaseController # Inherits admin security and helper methods from Admin::BaseController
    MANUAL_EXTRA_PRODUCTS = {
      "phantasmalflames" => [
        [ "collection_box", "First Partner Illustration Collection Series 1", "phantasmalflames_firstpartnerseries1.png" ],
        [ "collection_box", "Pokémon Day 2026 Collection", "phantasmalflames_pokemonday2026collection.png" ],
        [ "tin", "Mega Charizard Y Ex Tin", "phantasmalflames_megacharizardyextin.png" ],
        [ "tin", "Mega Charizard X Ex Tin", "phantasmalflames_megacharizardxextin.png" ]
      ],
      "destinedrivals" => [
        [ "booster_pack", "Booster Pack", "destinedrivals_booster.png" ],
        [ "ultra_premium_collection", "Team Rocket's Moltres Ultra Premium Collection", "destinedrivals_teamrocketsmoltresultrapremiumcollection.png" ],
        [ "half_booster_box", "Half Booster Box (18 Packs)", "destinedrivals_halfboosterbox.png" ]
      ],
      "151" => [
        [ "mini_tin", "Mini Tin", "151_minitin.png" ],
        [ "mini_tin_display", "Mini Tin Display", "151_minitindisplay.png" ]
      ],
      "prismaticevolutions" => [
        [ "mini_tin", "Mini Tin", "prismaticevolutions_minitin.png" ],
        [ "mini_tin_display", "Mini Tin Display", "prismaticevolutions_minitindisplay.png" ]
      ],
      "ascendedheroes" => [
        [ "mini_tin", "Mini Tin", "ascendedheroes_minitin.png" ],
        [ "mini_tin_display", "Mini Tin Display", "ascendedheroes_minitindisplay.png" ],
        [ "collection_box", "Mega Feraligatr Ex Box", "ascendedheroes_megaferaligatrexbox.png" ],
        [ "collection_box", "Mega Meganium Ex Box", "ascendedheroes_megameganiumexbox.png" ],
        [ "collection_box", "Mega Emboar Ex Box", "ascendedheroes_megaemboarexbox.png" ],
        [ "collection_box", "First Partners Deluxe Pin Collection", "ascendedheroes_firstpartnersdeluxepincollection.png" ],
        [ "collection_box", "Mega Lucario Premium Poster Collection", "ascendedheroes_megalucariopremiumpostercollection.png" ],
        [ "collection_box", "Mega Gardevoir Premium Poster Collection", "ascendedheroes_megagardevoirpremiumpostercollection.png" ],
        [ "blister_pack", "Charmander Tech Sticker Collection", "ascendedheroes_charmandertechstickercollection.png" ],
        [ "blister_pack", "Gastly Tech Sticker Collection", "ascendedheroes_gastlytechstickercollection.png" ],
        [ "blister_pack", "Erika's Tangela 2-Pack Blister", "ascendedheroes_erikastangela2packblister.png" ],
        [ "blister_pack", "Larry's Komala 2-Pack Blister", "ascendedheroes_larryskomala2packblister.png" ],
        [ "blister_pack_display", "2-Pack Blister Display", "ascendedheroes2packblisterdisplay.png" ],
        [ "blister_pack_display", "Tech Sticker Collection Display", "ascendedheroes_techstickercollectiondisplay.png" ]
      ]
    }.transform_values do |products|
      products.map do |type, name, image|
        { "type" => type, "name" => name, "img" => "images/sealed/#{image}" }
      end
    end.freeze

    # Loads the admin products page.
    def index
      @groups = build_groups
    end

    # Updates all product values submitted from the admin products table.
    def update_product_values
      values = normal_hash(params[:values])
      names = normal_hash(params[:names])
      set_names = normal_hash(params[:set_names])
      eras = normal_hash(params[:eras])
      product_type_names = normal_hash(params[:product_type_names])
      image_urls = normal_hash(params[:image_urls])

      changed = 0

      Product.transaction do
        values.each do |sku, raw_value|
          next if sku.to_s.strip.blank?
          next if raw_value.to_s.strip.blank?

          value = BigDecimal(raw_value.to_s.strip)
          raise ActionController::BadRequest if value.negative?
          raise ActionController::BadRequest if value > 1_000_000

          product = save_admin_product!(
            sku: sku,
            value: value,
            name: names[sku],
            set_name: set_names[sku],
            era: eras[sku],
            product_type: product_type_names[sku],
            image: image_urls[sku]
          )

          Product.update_holdings!(product) if Product.respond_to?(:update_holdings!)

          changed += 1
        end
      end

      redirect_to admin_products_path, notice: "#{changed} value(s) updated.", status: :see_other
    end

    private

    # Saves one admin product value into the products table and records the change.
    def save_admin_product!(sku:, value:, name:, set_name:, era:, product_type:, image:)
      product = Product.lock.find_or_initialize_by(sku: sku.to_s.strip)
      old_value = product.value

      product.name = name.to_s.strip.presence || "Product"
      product.value = value
      product.set_name = set_name.to_s.strip if product.respond_to?(:set_name=)
      product.era = era.to_s.strip if product.respond_to?(:era=)
      product.product_type = product_type.to_s.strip if product.respond_to?(:product_type=)
      product.image = image.to_s.strip if product.respond_to?(:image=)

      product.save!

      AdminAudit.record_change!(
        user: current_user,
        product: product,
        old_value: old_value,
        new_value: value,
        request: request
      )

      product
    end

    # Builds grouped product rows for the admin products table.
    def build_groups
      products = product_rows
      grouped = products.group_by { |row| row[:type_name] }
      preferred_order = type_map.values.uniq

      (preferred_order + (grouped.keys - preferred_order).sort).filter_map do |type_name|
        rows = grouped[type_name]
        next if rows.blank?

        [ type_name, rows.sort_by { |row| [ -row[:release_key], row[:set_index], row[:product_index] ] } ]
      end
    end

    # Builds the full flat product list from JSON data, manual products and database overrides.
    def product_rows
      data = merge_manual_products(sets_data)
      overrides = Product.all.index_by { |product| product.sku.to_s }
      images_folder = Rails.root.join("app", "assets", "images", "sealed")
      rows = []

      data.values.each_with_index do |set, set_index|
        Array(set["products"] || set["sealed"]).each_with_index do |product, product_index|
          row = build_row(set, product, set_index, product_index, overrides, images_folder)
          rows << row if row
        end
      end

      rows
    end

    # Builds one admin product row.
    def build_row(set, product, set_index, product_index, overrides, images_folder)
      set_slug = set["slug"].to_s
      type_code = Product.normalize_type(product["type"])

      return nil if set_slug.blank? || type_code.blank?

      name = product["name"].to_s
      type_name = type_map[type_code] || type_code.tr("_", " ").titleize
      route_type = build_route_type(type_code, name)
      sku = Product.value_override_sku(set_slug: set_slug, route_type: route_type)

      {
        sku: sku,
        type_name: type_name,
        product_name: name.presence || type_name,
        img_url: product_image(product["img"], images_folder),
        href: set_product_path(slug: set_slug, type: route_type),
        era: set["era"].to_s,
        set_slug: set_slug,
        set_name: set["name"].to_s,
        release_key: date_key(set["releaseDate"]),
        release_date: display_date(set["releaseDate"]),
        route_type: route_type,
        listings: marketplace_listing_quantity(set_slug, route_type, type_name),
        value: override_value(overrides, set_slug, route_type, type_code) || fallback_value(product),
        set_index: set_index,
        product_index: product_index
      }
    end

    # Merges manually listed extra products into the catalogue data.
    def merge_manual_products(data)
      MANUAL_EXTRA_PRODUCTS.each do |slug, products|
        set = data[slug] || data.values.find { |row| row["slug"].to_s == slug }
        next unless set

        key = set.key?("products") ? "products" : "sealed"
        set[key] = Array(set[key] || set["products"] || set["sealed"])

        products.each do |product|
          already_exists = set[key].any? do |existing|
            Product.normalize_text(existing["name"]) == Product.normalize_text(product["name"]) &&
              Product.normalize_type(existing["type"]) == Product.normalize_type(product["type"])
          end

          set[key] << product unless already_exists
        end
      end

      data
    end

    # Finds an existing admin override value for a product.
    def override_value(overrides, set_slug, route_type, type_code)
      override_skus(set_slug, route_type, type_code).each do |sku|
        value = overrides[sku]&.value
        return value if value.present?
      end

      nil
    end

    # Builds possible SKU formats for matching old and new product value rows.
    def override_skus(set_slug, route_type, type_code)
      skus = [
        Product.value_override_sku(set_slug: set_slug, route_type: route_type),
        "#{set_slug}:#{route_type}"
      ]

      unless Product.route_needs_product_slug?(type_code) && route_type.include?("--p-")
        skus << Product.value_override_sku(set_slug: set_slug, route_type: type_code)
        skus << "#{set_slug}:#{type_code}"
      end

      skus.map(&:to_s).uniq
    end

    # Counts active marketplace listings for a product.
    def marketplace_listing_quantity(set_slug, route_type, type_name)
      return 0 unless defined?(MarketplaceListing)

      scope = MarketplaceListing.active

      checks = [
        scope.where(set_slug: set_slug, route_type: route_type),
        scope.where(product_sku: "#{set_slug}:#{route_type}"),
        scope.where(product_sku: "#{set_slug}--#{route_type}"),
        scope.where(set_slug: set_slug, product_type_name: type_name)
      ]

      checks.each do |query|
        quantity = query.sum(:quantity).to_i
        return quantity if quantity.positive?
      end

      0
    rescue
      0
    end

    # Returns the product image path for the admin table.
    def product_image(image_path, images_folder)
      file = File.basename(image_path.to_s)
      return safe_asset_path("sealed/#{file}") if file.present? && File.exist?(images_folder.join(file))

      safe_asset_path("pokevaluelogo.png")
    end

    # Returns the fallback value from catalogue product data.
    def fallback_value(product)
      product["value"] || product["product_value"] || product["estimated_value"] || product["price"]
    end

    # Returns product type display names used by the public product pages.
    def type_map
      PagesController::PRODUCT_TYPE_NAMES
    rescue
      {}
    end

    # Builds the route type used in public product URLs.
    def build_route_type(type_code, name)
      route = Product.normalize_type(type_code)
      variant = name.to_s[/\(([^)]+)\)/, 1].to_s.strip
      origin = route == "pc_etb" || name.to_s.downcase.include?("pokemon center") ? "Pokemon Center" : ""

      route += "--v-#{slugify(variant)}" if variant.present?
      route += "--o-#{slugify(origin)}" if origin.present?
      route += "--p-#{slugify(name)}" if Product.route_needs_product_slug?(route) && name.present?

      route
    end

    # Converts text into a URL-safe slug.
    def slugify(value)
      Product.normalize_text(value).gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
    end
  end
end
