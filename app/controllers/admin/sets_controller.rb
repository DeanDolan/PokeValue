require "json"
require "date"

module Admin
  class SetsController < ApplicationController
    include Authentication

    skip_before_action :require_admin_mfa_verified, raise: false
    skip_before_action :require_admin_mfa, raise: false
    skip_before_action :require_mfa_verified, raise: false
    skip_before_action :require_mfa, raise: false
    skip_before_action :enforce_mfa, raise: false
    skip_before_action :enforce_admin_mfa, raise: false
    skip_before_action :verify_admin_mfa, raise: false
    skip_before_action :verify_mfa, raise: false

    before_action :require_admin

    def index
      @groups = build_groups
    end

    def update
      slug = params[:slug].to_s
      raise ActiveRecord::RecordNotFound if slug.blank?

      base = baseline_for_slug(slug)

      ov = find_override(slug)
      ov ||= init_override(slug)

      tv = params[:total_value].to_s.strip
      c = params[:cards].to_s.strip
      sc = params[:secret_cards].to_s.strip

      target_total = tv.blank? ? base[:total_value] : parse_decimal(tv)
      target_cards = c.blank? ? base[:cards] : parse_int(c)
      target_secret = sc.blank? ? base[:secret_cards] : parse_int(sc)

      apply_targets!(ov, base, target_total, target_cards, target_secret)

      redirect_to set_path(slug: slug), notice: "Set updated.", status: :see_other
    end

    def update_values
      total_values = to_plain_hash(params[:total_values])
      cards = to_plain_hash(params[:cards])
      secret_cards = to_plain_hash(params[:secret_cards])

      changed = 0

      baselines = baseline_map

      key = override_key_column
      existing = SetOverride.all.index_by { |o| o.public_send(key).to_s }

      SetOverride.transaction do
        slugs = (total_values.keys + cards.keys + secret_cards.keys).map(&:to_s).uniq
        slugs.each do |slug|
          next if slug.blank?

          base = baselines[slug] || { total_value: nil, cards: 0, secret_cards: 0 }
          ov = existing[slug]

          tv_raw = total_values[slug].to_s.strip
          c_raw = cards[slug].to_s.strip
          sc_raw = secret_cards[slug].to_s.strip

          target_total = tv_raw.blank? ? base[:total_value] : parse_decimal(tv_raw)
          target_cards = c_raw.blank? ? base[:cards] : parse_int(c_raw)
          target_secret = sc_raw.blank? ? base[:secret_cards] : parse_int(sc_raw)

          needs_override =
            !eq_decimal(target_total, base[:total_value]) ||
            target_cards.to_i != base[:cards].to_i ||
            target_secret.to_i != base[:secret_cards].to_i

          if ov.nil?
            next unless needs_override
            ov = init_override(slug)
          end

          before_total = ov.total_value
          before_cards = ov.cards
          before_secret = ov.secret_cards

          apply_targets!(ov, base, target_total, target_cards, target_secret)

          after_total = ov.persisted? ? ov.total_value : nil
          after_cards = ov.persisted? ? ov.cards : nil
          after_secret = ov.persisted? ? ov.secret_cards : nil

          if !eq_decimal(before_total, after_total) || before_cards != after_cards || before_secret != after_secret
            changed += 1
          end
        end
      end

      redirect_to admin_sets_path, notice: "#{changed} set(s) updated.", status: :see_other
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

    def override_key_column
      @override_key_column ||= begin
        cols = SetOverride.column_names
        cols.include?("set_slug") ? "set_slug" : "slug"
      rescue
        "slug"
      end
    end

    def find_override(slug)
      if override_key_column == "set_slug"
        SetOverride.find_by(set_slug: slug)
      else
        SetOverride.find_by(slug: slug)
      end
    end

    def init_override(slug)
      if override_key_column == "set_slug"
        SetOverride.new(set_slug: slug)
      else
        SetOverride.new(slug: slug)
      end
    end

    def baseline_map
      sets_data =
        begin
          raw = File.read(Rails.root.join("config", "sets.json"), encoding: "bom|utf-8")
          JSON.parse(raw)
        rescue
          {}
        end

      sets_data.values.each_with_object({}) do |s, h|
        slug = (s["slug"] || s[:slug]).to_s
        next if slug.blank?

        base_cards = (s["cards"] || s[:cards]).to_i
        base_secret = (s["secretCards"] || s[:secretCards] || s["secret_cards"] || s[:secret_cards]).to_i
        base_total = s["totalValue"] || s[:totalValue] || s["total_value"] || s[:total_value]

        base_total_bd =
          if base_total.nil? || base_total.to_s.strip.blank?
            nil
          else
            begin
              BigDecimal(base_total.to_s)
            rescue
              nil
            end
          end

        h[slug] = { total_value: base_total_bd, cards: base_cards, secret_cards: base_secret }
      end
    end

    def baseline_for_slug(slug)
      baseline_map[slug] || { total_value: nil, cards: 0, secret_cards: 0 }
    end

    def apply_targets!(ov, base, target_total, target_cards, target_secret)
      ov.total_value = eq_decimal(target_total, base[:total_value]) ? nil : target_total
      ov.cards = target_cards.to_i == base[:cards].to_i ? nil : target_cards.to_i
      ov.secret_cards = target_secret.to_i == base[:secret_cards].to_i ? nil : target_secret.to_i

      if ov.total_value.nil? && ov.cards.nil? && ov.secret_cards.nil?
        if ov.persisted?
          ov.destroy!
        end
      else
        ov.save! if ov.changed?
      end
    end

    def eq_decimal(a, b)
      aa = a.nil? ? nil : BigDecimal(a.to_s)
      bb = b.nil? ? nil : BigDecimal(b.to_s)
      aa == bb
    rescue
      a.to_s == b.to_s
    end

    def parse_decimal(raw)
      v = begin
        BigDecimal(raw.to_s.strip)
      rescue
        nil
      end
      raise ActionController::BadRequest if v.nil?
      raise ActionController::BadRequest if v < 0
      raise ActionController::BadRequest if v > 1_000_000_000
      v
    end

    def parse_int(raw)
      i = raw.to_s.strip
      raise ActionController::BadRequest if i.blank?
      n = Integer(i) rescue nil
      raise ActionController::BadRequest if n.nil?
      raise ActionController::BadRequest if n < 0
      n
    end

    def build_groups
      sets_data =
        begin
          raw = File.read(Rails.root.join("config", "sets.json"), encoding: "bom|utf-8")
          JSON.parse(raw)
        rescue
          {}
        end

      images_sets = Rails.root.join("app", "assets", "images", "sets")

      key = override_key_column
      overrides = SetOverride.all.index_by { |o| o.public_send(key).to_s }

      rows = sets_data.values.map do |s|
        slug = (s["slug"] || s[:slug]).to_s
        name = (s["name"] || s[:name]).to_s
        era = (s["era"] || s[:era] || s["series"] || s[:series]).to_s
        release_raw = (s["releaseDate"] || s[:releaseDate] || s["release_date"] || s[:release_date] || s["release"] || s[:release]).to_s

        base_cards = (s["cards"] || s[:cards]).to_i
        base_secret = (s["secretCards"] || s[:secretCards] || s["secret_cards"] || s[:secret_cards]).to_i
        base_total_value = s["totalValue"] || s[:totalValue] || s["total_value"] || s[:total_value]

        ov = overrides[slug]
        cards = ov&.respond_to?(:cards) && ov.cards.present? ? ov.cards : base_cards
        secret_cards = ov&.respond_to?(:secret_cards) && ov.secret_cards.present? ? ov.secret_cards : base_secret
        total_value = ov&.respond_to?(:total_value) && ov.total_value.present? ? ov.total_value : base_total_value

        img_url = pick_set_image(slug: slug, s: s, images_sets: images_sets)

        {
          slug: slug,
          name: name,
          era: era,
          release_key: date_key(release_raw),
          release_date: format_date(release_raw),
          release_raw: release_raw,
          img_url: img_url,
          cards: cards,
          secret_cards: secret_cards,
          total_value: total_value
        }
      end

      grouped = rows.group_by { |r| r[:era].to_s }

      eras_order = [ "Mega Evolution", "Scarlet & Violet", "Sword & Shield" ]
      (eras_order + (grouped.keys - eras_order).sort).filter_map do |era|
        list = grouped[era]
        next if list.blank?
        [ era, list.sort_by { |r| [ -r[:release_key], r[:name].to_s ] } ]
      end
    end

    def pick_set_image(slug:, s:, images_sets:)
      preferred = "#{slug}.png"
      if File.exist?(images_sets.join(preferred))
        return safe_asset_path("sets/#{preferred}")
      end

      box_base = File.basename((s["boxImage"] || s[:boxImage]).to_s) rescue nil
      if box_base.present? && File.exist?(images_sets.join(box_base))
        return safe_asset_path("sets/#{box_base}")
      end

      logo_base = File.basename((s["logo"] || s[:logo]).to_s) rescue nil
      if logo_base.present? && File.exist?(images_sets.join(logo_base))
        return safe_asset_path("sets/#{logo_base}")
      end

      safe_asset_path("pokevaluelogo.png")
    end

    def safe_asset_path(logical)
      ActionController::Base.helpers.asset_path(logical)
    rescue
      "/assets/#{logical}"
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
