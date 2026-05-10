require "json"
require "date"

module Admin
  class SetsController < BaseController
    def index
      @groups = build_groups
    end

    # Updates one set from a single set admin form.
    def update
      slug = params[:slug].to_s.strip
      raise ActiveRecord::RecordNotFound if slug.blank?

      base = baseline_map[slug] || empty_baseline
      override = SetOverride.find_or_initialize_by(slug: slug)

      total_value = params[:total_value].to_s.strip.presence
      cards = params[:cards].to_s.strip.presence
      secret_cards = params[:secret_cards].to_s.strip.presence

      apply_override!(
        override,
        base,
        total_value ? decimal_param(total_value, max: 1_000_000_000) : base[:total_value],
        cards ? integer_param(cards) : base[:cards],
        secret_cards ? integer_param(secret_cards) : base[:secret_cards]
      )

      redirect_to set_path(slug: slug), notice: "Set updated.", status: :see_other
    end

    # Updates all edited set values from the admin sets table.
    def update_values
      total_values = param_hash(params[:total_values])
      cards = param_hash(params[:cards])
      secret_cards = param_hash(params[:secret_cards])
      baselines = baseline_map
      changed = 0

      SetOverride.transaction do
        (total_values.keys + cards.keys + secret_cards.keys).map(&:to_s).uniq.each do |slug|
          next if slug.blank?

          base = baselines[slug] || empty_baseline
          override = SetOverride.find_or_initialize_by(slug: slug)

          changed += 1 if apply_override!(
            override,
            base,
            value_or_baseline(total_values[slug], base[:total_value], :decimal),
            value_or_baseline(cards[slug], base[:cards], :integer),
            value_or_baseline(secret_cards[slug], base[:secret_cards], :integer)
          )
        end
      end

      redirect_to admin_sets_path, notice: "#{changed} set(s) updated.", status: :see_other
    end

    private

    # Builds rows grouped by era for the admin sets page.
    def build_groups
      rows = sets_data.values.map do |set|
        slug = set["slug"].to_s
        base = baseline_map[slug] || empty_baseline
        override = SetOverride.find_by(slug: slug)

        {
          slug: slug,
          name: set["name"].to_s,
          era: set["era"].to_s,
          release_key: date_key(set["releaseDate"]),
          release_date: display_date(set["releaseDate"]),
          release_raw: set["releaseDate"].to_s,
          img_url: set_image(set),
          cards: override&.cards || base[:cards],
          secret_cards: override&.secret_cards || base[:secret_cards],
          total_value: override&.total_value || base[:total_value]
        }
      end

      grouped = rows.group_by { |row| row[:era] }
      era_order = [ "Mega Evolution", "Scarlet & Violet", "Sword & Shield" ]

      (era_order + (grouped.keys - era_order).sort).filter_map do |era|
        list = grouped[era]
        next if list.blank?

        [ era, list.sort_by { |row| [ -row[:release_key], row[:name] ] } ]
      end
    end

    # Builds the original JSON values so overrides only store changed values.
    def baseline_map
      @baseline_map ||= sets_data.values.each_with_object({}) do |set, hash|
        slug = set["slug"].to_s
        next if slug.blank?

        hash[slug] = {
          total_value: decimal_or_nil(set["totalValue"] || set["total_value"]),
          cards: set["cards"].to_i,
          secret_cards: (set["secretCards"] || set["secret_cards"]).to_i
        }
      end
    end

    # Saves changed set values, or deletes the override when values match the JSON baseline.
    def apply_override!(override, base, total_value, cards, secret_cards)
      was_persisted = override.persisted?

      override.total_value = same_decimal?(total_value, base[:total_value]) ? nil : total_value
      override.cards = cards.to_i == base[:cards].to_i ? nil : cards.to_i
      override.secret_cards = secret_cards.to_i == base[:secret_cards].to_i ? nil : secret_cards.to_i

      if override.total_value.nil? && override.cards.nil? && override.secret_cards.nil?
        override.destroy! if override.persisted?
        return was_persisted
      end

      changed = override.changed? || !override.persisted?
      override.save! if changed
      changed
    end

    # Uses a submitted value when present, otherwise keeps the JSON baseline.
    def value_or_baseline(value, baseline, type)
      raw = value.to_s.strip
      return baseline if raw.blank?
      return decimal_param(raw, max: 1_000_000_000) if type == :decimal

      integer_param(raw)
    end

    # Finds the best set image available in app/assets/images/sets.
    def set_image(set)
      folder = Rails.root.join("app", "assets", "images", "sets")
      slug_file = "#{set["slug"]}.png"
      box_file = File.basename(set["boxImage"].to_s)
      logo_file = File.basename(set["logo"].to_s)

      return safe_asset_path("sets/#{slug_file}") if File.exist?(folder.join(slug_file))
      return safe_asset_path("sets/#{box_file}") if box_file.present? && File.exist?(folder.join(box_file))
      return safe_asset_path("sets/#{logo_file}") if logo_file.present? && File.exist?(folder.join(logo_file))

      safe_asset_path("pokevaluelogo.png")
    end

    # Converts stored JSON decimal values safely.
    def decimal_or_nil(value)
      return nil if value.to_s.strip.blank?

      BigDecimal(value.to_s)
    rescue
      nil
    end

    # Compares decimal values without being affected by string formatting.
    def same_decimal?(left, right)
      return true if left.nil? && right.nil?
      return false if left.nil? || right.nil?

      BigDecimal(left.to_s) == BigDecimal(right.to_s)
    rescue
      left.to_s == right.to_s
    end

    # Empty fallback values used when a set is missing from config/sets.json.
    def empty_baseline
      { total_value: nil, cards: 0, secret_cards: 0 }
    end
  end
end
