require "json"
require "date"

module Admin
  class ProductsController < BaseController
    # These are extra sealed products that I want shown on the admin products page,
    # but they are not already in config/sets.json.
    # I am keeping them here so they can still appear in the admin table without
    # needing to manually rewrite the full JSON catalogue.
    #
    # Structure:
    # set slug => [
    #   [product type, product name, image file]
    # ]
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
      # This changes the short array format above into the same hash format that the rest of
      # the product catalogue uses.
      # Example:
      # [ "tin", "Mega Charizard X Ex Tin", "image.png" ]
      # becomes:
      # { "type" => "tin", "name" => "Mega Charizard X Ex Tin", "img" => "images/sealed/image.png" }
      products.map do |type, name, image|
        { "type" => type, "name" => name, "img" => "images/sealed/#{image}" }
      end
    end.freeze

    # This loads the admin products page.
    # @groups is what the view uses to display product rows grouped by product type.
    def index
      @groups = build_groups
    end

    # This updates all product values that were edited in the admin products table.
    # The form sends multiple values at once, so this loops through each submitted SKU/value pair.
    def update_values
      # Convert the Rails params into normal Ruby hashes.
      # These hashes all use the product SKU as the key.
      values = param_hash(params[:values])
      names = param_hash(params[:names])
      set_names = param_hash(params[:set_names])
      eras = param_hash(params[:eras])
      product_type_names = param_hash(params[:product_type_names])
      image_urls = param_hash(params[:image_urls])

      # Counts how many product values were actually changed.
      changed = 0

      # Keep all product updates inside one database transaction.
      # If something goes wrong halfway through, Rails can roll everything back.
      Product.transaction do
        values.each do |sku, raw_value|
          # Skip blank SKUs because there is no product to update.
          next if sku.to_s.strip.blank?

          # Skip blank values so empty admin inputs do not overwrite saved values.
          next if raw_value.to_s.strip.blank?

          # Save or update the product value.
          # decimal_param checks that the value is valid, not negative, and not above the max allowed amount.
          product = save_product_value!(
            sku: sku,
            value: decimal_param(raw_value, max: 1_000_000),
            name: names[sku],
            set_name: set_names[sku],
            era: eras[sku],
            product_type: product_type_names[sku],
            image: image_urls[sku]
          )

          # After changing a product value, refresh any user holdings that use this product.
          # This keeps portfolio totals up to date after admin changes.
          Product.refresh_holdings_for_product!(product) if Product.respond_to?(:refresh_holdings_for_product!)

          # Add 1 to the number of changed values.
          changed += 1
        end
      end

      # Send the admin back to the products admin page with a success message.
      redirect_to admin_products_path, notice: "#{changed} value(s) updated.", status: :see_other
    end

    private

    # This saves one product value from the admin page and records the change in the admin audit log.
    # It is used by update_values above.
    def save_product_value!(sku:, value:, name:, set_name:, era:, product_type:, image:)
      # Find the product by SKU or create a new unsaved product if it does not exist yet.
      # lock is used so two updates cannot change the same product row at the exact same time.
      product = Product.lock.find_or_initialize_by(sku: sku.to_s.strip)

      # Store the old value before changing it.
      # This is needed so the audit log can show the before and after value.
      old_value = product.value

      # Save the product name.
      # If the admin leaves the name blank, use "Product" as a safe fallback.
      product.name = name.to_s.strip.presence || "Product"

      # Save the new product value.
      product.value = value

      # These fields are only set if the Product model supports them.
      # This stops the controller breaking if a column/method does not exist.
      product.set_name = set_name.to_s.strip if product.respond_to?(:set_name=)
      product.era = era.to_s.strip if product.respond_to?(:era=)
      product.product_type = product_type.to_s.strip if product.respond_to?(:product_type=)
      product.image = image.to_s.strip if product.respond_to?(:image=)

      # Save the product to the database.
      # save! will raise an error if the save fails, which is useful because this is admin data.
      product.save!

      # Record the value change in the admin audit table.
      # This lets me track who changed a value and what the old/new values were.
      AdminAudit.record_change!(
        user: current_user,
        product: product,
        old_value: old_value,
        new_value: value,
        request: request
      )

      # Return the product so update_values can refresh holdings for it.
      product
    end

    # This builds the grouped product data used by the admin products table.
    # Products are grouped by type, for example ETB, Booster Box, Booster Bundle, etc.
    def build_groups
      # Get one flat list of all product rows first.
      products = product_rows

      # Group the rows by their display type name.
      grouped = products.group_by { |row| row[:type_name] }

      # This gives the admin table a sensible order based on the product type names
      # used by the public product pages.
      preferred_order = type_map.values.uniq

      # Build the final grouped structure for the view.
      # It keeps preferred product types first, then adds any extra types alphabetically.
      (preferred_order + (grouped.keys - preferred_order).sort).filter_map do |type_name|
        rows = grouped[type_name]

        # Skip empty groups.
        next if rows.blank?

        # Sort products within each group.
        # Newer releases come first because release_key is reversed with -row[:release_key].
        # set_index and product_index keep the original JSON order as a backup sorting method.
        [ type_name, rows.sort_by { |row| [ -row[:release_key], row[:set_index], row[:product_index] ] } ]
      end
    end

    # This builds one flat list of product rows for the admin table.
    # It starts from config/sets.json, adds manual extra products, then applies any database overrides.
    def product_rows
      # Load JSON data and merge in the manually added products from MANUAL_EXTRA_PRODUCTS.
      data = merge_manual_products(sets_data)

      # Load existing Product records from the database and index them by SKU.
      # These are used as admin override values.
      overrides = Product.all.index_by { |product| product.sku.to_s }

      # This is the folder where sealed product images are stored.
      images_folder = Rails.root.join("app", "assets", "images", "sealed")

      rows = []

      # Loop through every set in the JSON data.
      data.values.each_with_index do |set, set_index|
        # Some sets use "products" and some use "sealed", so this supports both.
        Array(set["products"] || set["sealed"]).each_with_index do |product, product_index|
          # Build one admin table row for this product.
          row = build_row(set, product, set_index, product_index, overrides, images_folder)

          # Only add the row if build_row returned a valid row.
          rows << row if row
        end
      end

      rows
    end

    # This builds one row of product data for the admin products table.
    # Each row contains everything the view needs, such as name, image, value, set, route and listing count.
    def build_row(set, product, set_index, product_index, overrides, images_folder)
      # Get the set slug from the JSON set data.
      set_slug = set["slug"].to_s

      # Normalise the product type so the app uses one consistent format.
      type_code = Product.normalize_type(product["type"])

      # If the set slug or type is missing, skip this product.
      return nil if set_slug.blank? || type_code.blank?

      # Product name from the JSON/manual product data.
      name = product["name"].to_s

      # Convert the product type code into the friendly display name.
      # If no friendly name exists, turn the type code into title case.
      type_name = type_map[type_code] || type_code.tr("_", " ").titleize

      # Build the route type used in public product URLs.
      # This needs to match the same route format used by the product pages.
      route_type = build_route_type(type_code, name)

      # Build the SKU used for admin value overrides.
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

    # This adds the MANUAL_EXTRA_PRODUCTS into the main JSON catalogue data.
    # It also checks for duplicates so the same product does not appear twice.
    def merge_manual_products(data)
      MANUAL_EXTRA_PRODUCTS.each do |slug, products|
        # Find the set by hash key first.
        # If that does not work, find it by checking the set slug inside the row.
        set = data[slug] || data.values.find { |row| row["slug"].to_s == slug }

        # If the set does not exist in the JSON data, skip it.
        next unless set

        # Some sets store products under "products" and some under "sealed".
        # This chooses whichever key the set already uses.
        key = set.key?("products") ? "products" : "sealed"

        # Make sure the product list is always an array.
        set[key] = Array(set[key] || set["products"] || set["sealed"])

        products.each do |product|
          # Check whether this manual product already exists in the set.
          # Both name and type are compared after normalising, so small formatting differences do not create duplicates.
          already_exists = set[key].any? do |existing|
            Product.normalize_text(existing["name"]) == Product.normalize_text(product["name"]) &&
              Product.normalize_type(existing["type"]) == Product.normalize_type(product["type"])
          end

          # Add the manual product only if it is not already in the set.
          set[key] << product unless already_exists
        end
      end

      data
    end

    # This checks if the admin has already saved an override value for a product.
    # The Product table can store updated values that override the fallback value from config/sets.json.
    def override_value(overrides, set_slug, route_type, type_code)
      # Try each possible SKU format because older and newer rows may have used different SKU styles.
      override_skus(set_slug, route_type, type_code).each do |sku|
        value = overrides[sku]&.value

        # Return the first override value found.
        return value if value.present?
      end

      # If no override exists, return nil so the fallback value can be used.
      nil
    end

    # This builds all possible SKU formats for a product.
    # It is needed because some older product value rows may have been saved with a different SKU format.
    def override_skus(set_slug, route_type, type_code)
      skus = [
        Product.value_override_sku(set_slug: set_slug, route_type: route_type),
        "#{set_slug}:#{route_type}"
      ]

      # If the route does not need a product slug, also check the plain type code versions.
      # This helps match older admin override rows for simpler products.
      unless Product.route_needs_product_slug?(type_code) && route_type.include?("--p-")
        skus << Product.value_override_sku(set_slug: set_slug, route_type: type_code)
        skus << "#{set_slug}:#{type_code}"
      end

      # Convert everything to strings and remove duplicates.
      skus.map(&:to_s).uniq
    end

    # This works out how many active marketplace listings exist for this product.
    # It tries a few different matching styles because listings may store product identity in different ways.
    def marketplace_listing_quantity(set_slug, route_type, type_name)
      # If the MarketplaceListing model does not exist for some reason, return 0 instead of breaking the admin page.
      return 0 unless defined?(MarketplaceListing)

      # Only count active listings.
      scope = MarketplaceListing.active

      # Try different ways the same product could be stored in marketplace listings.
      checks = [
        scope.where(set_slug: set_slug, route_type: route_type),
        scope.where(product_sku: "#{set_slug}:#{route_type}"),
        scope.where(product_sku: "#{set_slug}--#{route_type}"),
        scope.where(set_slug: set_slug, product_type_name: type_name)
      ]

      # Return the first positive quantity found.
      checks.each do |query|
        quantity = query.sum(:quantity).to_i
        return quantity if quantity.positive?
      end

      # If nothing is found, show 0 listings.
      0
    rescue
      # If anything goes wrong while checking listings, return 0 so the admin page still loads.
      0
    end

    # This chooses the correct product image for the admin table.
    # It only uses the image if the file actually exists in app/assets/images/sealed.
    def product_image(image_path, images_folder)
      # Get only the file name from the image path.
      file = File.basename(image_path.to_s)

      # If the file exists in the sealed images folder, return the Rails asset path for it.
      return safe_asset_path("sealed/#{file}") if file.present? && File.exist?(images_folder.join(file))

      # If the image is missing, use the PokéValue logo as a fallback.
      safe_asset_path("pokevaluelogo.png")
    end

    # This gets the fallback product value from the JSON/manual product data.
    # Different products may use slightly different key names, so this checks all supported options.
    def fallback_value(product)
      product["value"] || product["product_value"] || product["estimated_value"] || product["price"]
    end

    # This reuses the same product type display names used on the public product pages.
    # If PagesController cannot be loaded for any reason, return an empty hash.
    def type_map
      PagesController::PRODUCT_TYPE_NAMES
    rescue
      {}
    end

    # This builds the route type used in product page URLs.
    # It needs to match the public product page route format so admin links go to the correct product page.
    def build_route_type(type_code, name)
      # Normalise the base type first.
      route = Product.normalize_type(type_code)

      # If the product name has a variant inside brackets, use it in the route.
      # Example: "Elite Trainer Box (Lucario)" gives variant "Lucario".
      variant = name.to_s[/\(([^)]+)\)/, 1].to_s.strip

      # Detect Pokemon Center products.
      # pc_etb products and names containing "pokemon center" get a Pokemon Center origin part in the route.
      origin = route == "pc_etb" || name.to_s.downcase.include?("pokemon center") ? "Pokemon Center" : ""

      # Add the variant part to the route if one exists.
      route += "--v-#{slugify(variant)}" if variant.present?

      # Add the origin part to the route if one exists.
      route += "--o-#{slugify(origin)}" if origin.present?

      # Some product types need the product name in the route so they do not clash with other products.
      route += "--p-#{slugify(name)}" if Product.route_needs_product_slug?(route) && name.present?

      route
    end

    # This turns text into safe URL-style text.
    # Example: "Mega Charizard X Ex Tin" becomes "mega-charizard-x-ex-tin".
    def slugify(value)
      Product.normalize_text(value).gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
    end
  end
end
