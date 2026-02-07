require "json"
require "date"

module Admin
  class ProductsController < ApplicationController
    include Authentication

    TYPE_MAP = {
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
    }.freeze

    before_action :require_admin

    def index
      @groups = build_groups
    end

    def update_values
      values = params[:values].is_a?(Hash) ? params[:values] : {}
      names = params[:names].is_a?(Hash) ? params[:names] : {}
      changed = 0

      Product.transaction do
        values.each do |sku, raw|
          sku = sku.to_s
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

          product =
            if Product.column_names.include?("sku")
              Product.find_or_initialize_by(sku: sku)
            else
              nil
            end
          raise ActiveRecord::RecordNotFound unless product

          old = product.respond_to?(:value) ? product.value : nil

          if product.respond_to?(:name) && product.name.to_s.strip.blank?
            product.name = name
          end

          if product.respond_to?(:value)
            product.value = value
          elsif product.respond_to?(:value_cents)
            product.value_cents = (value * 100).to_i
          else
            raise ActionController::BadRequest
          end

          product.save!

          if defined?(AdminAudit)
            AdminAudit.create!(
              user_id: current_user.id,
              sku: (product.respond_to?(:sku) ? product.sku.to_s : sku),
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
      sets_data =
        begin
          raw = File.read(Rails.root.join("config", "sets.json"), encoding: "bom|utf-8")
          JSON.parse(raw)
        rescue
          {}
        end

      images_sealed = Rails.root.join("app", "assets", "images", "sealed")
      overrides = Product.column_names.include?("sku") ? Product.all.index_by { |p| p.sku.to_s } : {}

      products = []

      sets_data.values.each do |s|
        set_slug = (s["slug"] || s[:slug]).to_s
        set_name = (s["name"] || s[:name]).to_s
        era = (s["era"] || s[:era] || s["series"] || s[:series]).to_s
        release_raw = (s["releaseDate"] || s[:releaseDate] || s["release_date"] || s[:release_date] || s["release"] || s[:release]).to_s
        release_key = date_key(release_raw)
        release_display = format_date(release_raw)

        Array(s["products"] || s[:products] || s["sealed"] || s[:sealed]).each do |p|
          type_code = (p["type"] || p[:type]).to_s
          next if type_code.blank?

          prod_name = (p["name"] || p[:name] || "").to_s
          base = normalize_type(type_code)
          type_name = TYPE_MAP[base] || base.tr("_", " ").split.map(&:capitalize).join(" ")
          route_type = build_route_type_for_product(type_key: base, name: prod_name)

          sku = build_value_override_sku(set_slug: set_slug, route_type: route_type)

          img_base = File.basename((p["img"] || p[:img]).to_s) rescue ""
          img_url =
            if img_base.present? && File.exist?(images_sealed.join(img_base))
              safe_asset_path("sealed/#{img_base}")
            else
              safe_asset_path("pokevaluelogo.png")
            end

          listings = (p["listings"] || p[:listings] || p["count"] || p[:count] || 0).to_i
          fallback_value =
            (p["value"] || p[:value] || p["product_value"] || p[:product_value] || p["estimated_value"] || p[:estimated_value] || p["price"] || p[:price])

          db_value = overrides[sku]&.respond_to?(:value) ? overrides[sku].value : nil

          href = set_product_path(slug: set_slug, type: route_type)

          products << {
            sku: sku,
            type_name: type_name,
            product_name: (prod_name.presence || type_name),
            img_url: img_url,
            href: href,
            era: era,
            set_name: set_name,
            release_key: release_key,
            release_date: release_display,
            listings: listings,
            value: (db_value.nil? ? fallback_value : db_value)
          }
        end
      end

      grouped = products.group_by { |x| x[:type_name] }

      ordered = TYPE_MAP.values.uniq
      (ordered + (grouped.keys - ordered).sort).filter_map do |k|
        rows = grouped[k]
        next if rows.blank?
        [ k, rows.sort_by { |r| [ -r[:release_key], r[:set_name].to_s, r[:product_name].to_s ] } ]
      end
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

    def build_route_type_for_product(type_key:, name:)
      base = normalize_type(type_key)
      variant = extract_variant(name)
      origin = infer_origin(type_key: type_key, name: name)

      out = base.dup
      out << "--v-#{slugify(variant)}" if variant.present?
      out << "--o-#{slugify(origin)}" if origin.present?
      out
    end

    def build_value_override_sku(set_slug:, route_type:)
      a = set_slug.to_s.strip.gsub(/[^a-zA-Z0-9\-_]+/, "-").gsub(/\A-+|-+\z/, "")
      b = route_type.to_s.strip.gsub(/[^a-zA-Z0-9\-_]+/, "-").gsub(/\A-+|-+\z/, "")
      "#{a}--#{b}"
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
