require "json" # Allows this controller to work with JSON catalogue data
require "date" # Allows this controller to parse and format release dates

module Admin # Groups this controller inside the admin namespace
  class SetsController < BaseController # Inherits admin security and helper methods from Admin::BaseController
    # Loads the admin sets page.
    def index
      @groups = build_groups
    end

    # Updates all set values submitted from the admin sets table.
    def update_set_values
      total_values = normal_hash(params[:total_values])
      changed = 0

      SetOverride.transaction do
        total_values.each do |slug, raw_value|
          next if slug.to_s.strip.blank?

          changed += 1 if save_admin_set!(
            slug: slug,
            total_value: raw_value
          )
        end
      end

      redirect_to admin_sets_path, notice: "#{changed} set(s) updated.", status: :see_other
    end

    private

    # Saves one admin set value into the set_overrides table.
    def save_admin_set!(slug:, total_value:)
      clean_slug = slug.to_s.strip
      raw_value = total_value.to_s.strip
      override = SetOverride.find_or_initialize_by(slug: clean_slug)

      if raw_value.blank?
        return false unless override.persisted?

        override.destroy!
        return true
      end

      override.total_value = safe_set_decimal(raw_value)
      override.cards = nil if override.respond_to?(:cards=)
      override.secret_cards = nil if override.respond_to?(:secret_cards=)

      return false unless override.changed? || !override.persisted?

      override.save!
      true
    end

    # Builds set rows for the admin sets page and groups them by era.
    def build_groups
      rows = set_rows
      grouped = rows.group_by { |row| row[:era] }
      era_order = [ "Mega Evolution", "Scarlet & Violet", "Sword & Shield" ]

      (era_order + (grouped.keys - era_order).sort).filter_map do |era|
        list = grouped[era]
        next if list.blank?

        [ era, list.sort_by { |row| [ -row[:release_key], row[:name] ] } ]
      end
    end

    # Builds every set row shown in the admin sets table.
    def set_rows
      sets_data.values.map do |set|
        build_set_row(set)
      end
    end

    # Builds one admin set row.
    def build_set_row(set)
      slug = set["slug"].to_s
      override = SetOverride.find_by(slug: slug)
      total_value = override&.total_value.present? ? override.total_value.to_s("F") : set_total_value(set)

      {
        slug: slug,
        name: set["name"].to_s,
        era: set["era"].to_s,
        release_key: date_key(set["releaseDate"]),
        release_date: display_date(set["releaseDate"]),
        release_raw: set["releaseDate"].to_s,
        img_url: set_image(set),
        total_value: total_value
      }
    end

    # Gets the original set value from config/sets.json.
    def set_total_value(set)
      raw_value = set["totalValue"] || set["total_value"]
      return "" if raw_value.to_s.strip.blank?

      BigDecimal(raw_value.to_s).to_s("F")
    rescue
      raw_value.to_s
    end

    # Converts a submitted set value into a safe BigDecimal.
    def safe_set_decimal(value)
      decimal = BigDecimal(value.to_s.strip)
      raise ActionController::BadRequest if decimal.negative?
      raise ActionController::BadRequest if decimal > 1_000_000_000

      decimal
    rescue
      raise ActionController::BadRequest
    end

    # Finds the best image to show for a set on the admin page.
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
  end
end
