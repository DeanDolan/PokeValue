require "json"
require "date"

module Admin
  class ProductsController < ApplicationController
    include Authentication

    TYPE_MAP = {
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
    }.freeze

    before_action :require_admin

    def index
      @groups = build_groups
    end

    def update_values
      values = to_plain_hash(params[:values])
      names = to_plain_hash(params[:names])
      set_names = to_plain_hash(params[:set_names])
      eras = to_plain_hash(params[:eras])
      product_type_names = to_plain_hash(params[:product_type_names])
      route_types = to_plain_hash(params[:route_types])
      image_urls = to_plain_hash(params[:image_urls])
      changed = 0

      Product.transaction do
        values.each do |sku, raw|
          sku = sku.to_s.strip
          next if sku.blank?

          raw_s = raw.to_s.strip
          next if raw_s.blank?

          value = begin
            BigDecimal(raw_s)
          rescue
            nil
          end

          raise ActionController::BadRequest if value.nil?
          raise ActionController::BadRequest if value < 0
          raise ActionController::BadRequest if value > 1_000_000

          name = names[sku].to_s.strip
          name = "Product" if name.blank?

          product = Product.lock.find_or_initialize_by(sku: sku)
          old = product.respond_to?(:value) ? product.value : nil

          product.name = name
          product.value = value
          product.set_name = set_names[sku].to_s.strip if product.respond_to?(:set_name=)
          product.era = eras[sku].to_s.strip if product.respond_to?(:era=)
          product.product_type = product_type_names[sku].to_s.strip if product.respond_to?(:product_type=)
          product.image = image_urls[sku].to_s.strip if product.respond_to?(:image=)

          product.save!

          Product.refresh_holdings_for_product!(product) if Product.respond_to?(:refresh_holdings_for_product!)

          if defined?(AdminAudit)
            AdminAudit.create!(
              user_id: current_user.id,
              sku: product.sku.to_s,
              old_value: old,
              new_value: value,
              ip: request.remote_ip,
              user_agent: request.user_agent.to_s
            )
          end

          changed += 1
        end
      end

      redirect_to admin_products_path, notice: "#{changed} value(s) updated.", status: :see_other
    end

    private

    def to_plain_hash(obj)
      return obj.to_unsafe_h if obj.is_a?(ActionController::Parameters)
      return obj if obj.is_a?(Hash)
      {}
    end

    def require_admin
      ok =
        if respond_to?(:admin_signed_in?)
          admin_signed_in?
        elsif respond_to?(:current_user) && current_user
          current_user.respond_to?(:admin?) ? current_user.admin? : false
        else
          false
        end

      redirect_to(root_path, alert: "Not authorized.", status: :see_other) unless ok
    end

    def build_groups
      sets_data = load_sets_data

      images_sealed = Rails.root.join("app", "assets", "images", "sealed")
      overrides = Product.column_names.include?("sku") ? Product.all.index_by { |p| p.sku.to_s } : {}

      products = []

      sets_data.values.each_with_index do |s, set_index|
        set_slug = (s["slug"] || s[:slug]).to_s
        set_name = (s["name"] || s[:name]).to_s
        era = (s["era"] || s[:era] || s["series"] || s[:series]).to_s
        release_raw = (s["releaseDate"] || s[:releaseDate] || s["release_date"] || s[:release_date] || s["release"] || s[:release]).to_s
        release_key = date_key(release_raw)
        release_display = format_date(release_raw)

        Array(s["products"] || s[:products] || s["sealed"] || s[:sealed]).each_with_index do |p, product_index|
          type_code = (p["type"] || p[:type]).to_s
          next if type_code.blank?

          prod_name = (p["name"] || p[:name] || "").to_s
          base = normalize_type(type_code)
          type_name = TYPE_MAP[base] || base.tr("_", " ").split.map(&:capitalize).join(" ")
          route_type = build_route_type_for_product(type_key: base, name: prod_name)

          sku = build_value_override_sku(set_slug: set_slug, route_type: route_type)
          fallback_skus = value_override_sku_candidates(set_slug: set_slug, route_type: route_type, type_code: base)

          img_base = File.basename((p["img"] || p[:img]).to_s) rescue ""
          img_url =
            if img_base.present? && File.exist?(images_sealed.join(img_base))
              safe_asset_path("sealed/#{img_base}")
            else
              safe_asset_path("pokevaluelogo.png")
            end

          fallback_value =
            (p["value"] || p[:value] || p["product_value"] || p[:product_value] || p["estimated_value"] || p[:estimated_value] || p["price"] || p[:price])

          db_value = nil
          fallback_skus.each do |candidate_sku|
            row = overrides[candidate_sku]
            if row&.respond_to?(:value)
              db_value = row.value
              break
            end
          end

          listings = marketplace_listing_quantity(set_slug: set_slug, route_type: route_type, type_name: type_name)

          href = set_product_path(slug: set_slug, type: route_type)

          products << {
            sku: sku,
            type_name: type_name,
            product_name: (prod_name.presence || type_name),
            img_url: img_url,
            href: href,
            era: era,
            set_slug: set_slug,
            set_name: set_name,
            release_key: release_key,
            release_date: release_display,
            route_type: route_type,
            listings: listings,
            value: (db_value.nil? ? fallback_value : db_value),
            set_index: set_index,
            product_index: product_index
          }
        end
      end

      grouped = products.group_by { |x| x[:type_name] }

      ordered = TYPE_MAP.values.uniq
      (ordered + (grouped.keys - ordered).sort).filter_map do |k|
        rows = grouped[k]
        next if rows.blank?
        [ k, rows.sort_by { |r| [ -r[:release_key], r[:set_index].to_i, r[:product_index].to_i ] } ]
      end
    end

    def load_sets_data
      raw = File.read(Rails.root.join("config", "sets.json"), encoding: "bom|utf-8")
      data = JSON.parse(raw)
      merge_manual_extra_products(data)
    rescue
      {}
    end

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

    def marketplace_listing_quantity(set_slug:, route_type:, type_name:)
      return 0 unless defined?(MarketplaceListing)

      quantity = MarketplaceListing.active.where(set_slug: set_slug.to_s, route_type: route_type.to_s).sum(:quantity).to_i

      if quantity.zero?
        quantity = MarketplaceListing.active.where(product_sku: "#{set_slug}:#{route_type}").sum(:quantity).to_i
      end

      if quantity.zero?
        quantity = MarketplaceListing.active.where(product_sku: "#{set_slug}--#{route_type}").sum(:quantity).to_i
      end

      if quantity.zero?
        quantity = MarketplaceListing.active.where(set_slug: set_slug.to_s, product_type_name: type_name.to_s).sum(:quantity).to_i
      end

      quantity
    rescue
      0
    end

    def safe_asset_path(logical)
      ActionController::Base.helpers.asset_path(logical)
    rescue
      "/assets/#{logical}"
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

    def build_route_type_for_product(type_key:, name:)
      base = normalize_type(type_key)
      variant = extract_variant(name)
      origin = infer_origin(type_key: type_key, name: name)

      out = base.dup
      out << "--v-#{slugify(variant)}" if variant.present?
      out << "--o-#{slugify(origin)}" if origin.present?
      out << "--p-#{slugify(name)}" if route_needs_product_slug?(base) && name.to_s.present?
      out
    end

    def build_value_override_sku(set_slug:, route_type:)
      Product.value_override_sku(set_slug: set_slug, route_type: route_type)
    end

    def value_override_sku_candidates(set_slug:, route_type:, type_code:)
      candidates = []
      candidates << build_value_override_sku(set_slug: set_slug, route_type: route_type)
      candidates << "#{set_slug}:#{route_type}"

      unless route_needs_product_slug?(type_code) && route_type.to_s.include?("--p-")
        candidates << build_value_override_sku(set_slug: set_slug, route_type: type_code)
        candidates << "#{set_slug}:#{type_code}"
      end

      candidates.map(&:to_s).uniq
    end

    def date_key(s)
      d = begin
        Date.parse(s.to_s)
      rescue
        nil
      end
      d ? d.jd : 0
    end

    def format_date(s)
      d = begin
        Date.parse(s.to_s)
      rescue
        nil
      end
      d ? d.strftime("%d/%m/%Y") : s.to_s
    end
  end
end
