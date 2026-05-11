require "json"
require "date"

module Admin
  class SetsController < BaseController
    # This loads the admin sets page.
    # @groups is used by the view to show sets grouped by era.
    def index
      @groups = build_groups
    end

    # This updates one set from a single admin form.
    # It is used when the admin edits one specific set and saves it.
    def update
      # Get the set slug from the URL params.
      # The slug identifies which set is being edited.
      slug = params[:slug].to_s.strip

      # If there is no slug, Rails treats it as not found.
      raise ActiveRecord::RecordNotFound if slug.blank?

      # Get the original values for this set from config/sets.json.
      # If the set cannot be found in the JSON file, use empty fallback values.
      base = baseline_map[slug] || empty_baseline

      # Find the existing override row for this set, or create a new unsaved one.
      # Overrides are stored in the database instead of editing config/sets.json directly.
      override = SetOverride.find_or_initialize_by(slug: slug)

      # Read the values submitted from the admin form.
      # presence makes blank strings turn into nil.
      total_value = params[:total_value].to_s.strip.presence
      cards = params[:cards].to_s.strip.presence
      secret_cards = params[:secret_cards].to_s.strip.presence

      # Save the override values.
      # If a value is blank, it keeps the original JSON baseline value.
      # decimal_param and integer_param also protect against bad admin input.
      apply_override!(
        override,
        base,
        total_value ? decimal_param(total_value, max: 1_000_000_000) : base[:total_value],
        cards ? integer_param(cards) : base[:cards],
        secret_cards ? integer_param(secret_cards) : base[:secret_cards]
      )

      # After saving, bring the admin back to the public set page so they can see the result.
      redirect_to set_path(slug: slug), notice: "Set updated.", status: :see_other
    end

    # This updates multiple set values from the admin sets table.
    # It is used when the admin edits several rows and saves them together.
    def update_values
      # Convert Rails params into normal Ruby hashes.
      # Each hash uses the set slug as the key.
      total_values = param_hash(params[:total_values])
      cards = param_hash(params[:cards])
      secret_cards = param_hash(params[:secret_cards])

      # Load the original JSON values for all sets.
      baselines = baseline_map

      # This counts how many sets were actually changed.
      changed = 0

      # Keep all set override updates inside one transaction.
      # If something fails halfway through, Rails can roll everything back.
      SetOverride.transaction do
        # Build one unique list of all slugs that appeared in any submitted field.
        (total_values.keys + cards.keys + secret_cards.keys).map(&:to_s).uniq.each do |slug|
          # Skip blank slugs because they cannot identify a set.
          next if slug.blank?

          # Get the original JSON values for this set.
          # If the set is missing for any reason, use empty fallback values.
          base = baselines[slug] || empty_baseline

          # Find or prepare the database override row for this set.
          override = SetOverride.find_or_initialize_by(slug: slug)

          # Apply the submitted values.
          # If apply_override! returns true, it means something changed, so the changed counter increases.
          changed += 1 if apply_override!(
            override,
            base,
            value_or_baseline(total_values[slug], base[:total_value], :decimal),
            value_or_baseline(cards[slug], base[:cards], :integer),
            value_or_baseline(secret_cards[slug], base[:secret_cards], :integer)
          )
        end
      end

      # Send the admin back to the admin sets page with a message showing how many sets changed.
      redirect_to admin_sets_path, notice: "#{changed} set(s) updated.", status: :see_other
    end

    private

    # This builds the set rows for the admin sets page.
    # The rows are grouped by era, such as Mega Evolution, Scarlet & Violet, and Sword & Shield.
    def build_groups
      # Turn each set from config/sets.json into a row that the admin view can display.
      rows = sets_data.values.map do |set|
        # Get the set slug.
        slug = set["slug"].to_s

        # Get the original JSON baseline values for this set.
        base = baseline_map[slug] || empty_baseline

        # Check if the admin has saved any override values for this set.
        override = SetOverride.find_by(slug: slug)

        {
          slug: slug,
          name: set["name"].to_s,
          era: set["era"].to_s,
          release_key: date_key(set["releaseDate"]),
          release_date: display_date(set["releaseDate"]),
          release_raw: set["releaseDate"].to_s,
          img_url: set_image(set),

          # These values use the database override if one exists.
          # If there is no override, they fall back to the original config/sets.json value.
          cards: override&.cards || base[:cards],
          secret_cards: override&.secret_cards || base[:secret_cards],
          total_value: override&.total_value || base[:total_value]
        }
      end

      # Group the rows by era so the admin page is easier to read.
      grouped = rows.group_by { |row| row[:era] }

      # This is the preferred order for eras on the admin page.
      era_order = [ "Mega Evolution", "Scarlet & Violet", "Sword & Shield" ]

      # Build the final grouped list.
      # Known eras are shown first in the chosen order.
      # Any other eras are added afterwards alphabetically.
      (era_order + (grouped.keys - era_order).sort).filter_map do |era|
        list = grouped[era]

        # Skip empty era groups.
        next if list.blank?

        # Sort each era group by newest release first, then by name.
        [ era, list.sort_by { |row| [ -row[:release_key], row[:name] ] } ]
      end
    end

    # This builds the original set values from config/sets.json.
    # These are the baseline values before any admin override is applied.
    # The point of this is that the database only needs to store changed values,
    # not a full copy of every set.
    def baseline_map
      @baseline_map ||= sets_data.values.each_with_object({}) do |set, hash|
        # Each set is identified by its slug.
        slug = set["slug"].to_s

        # Skip any set that does not have a slug.
        next if slug.blank?

        # Store the baseline values for this set.
        # Some JSON keys use camelCase and some may use snake_case, so both are checked.
        hash[slug] = {
          total_value: decimal_or_nil(set["totalValue"] || set["total_value"]),
          cards: set["cards"].to_i,
          secret_cards: (set["secretCards"] || set["secret_cards"]).to_i
        }
      end
    end

    # This applies the admin changes to a SetOverride record.
    # It only saves values that are different from the original JSON baseline.
    # If all values match the JSON baseline, the override is deleted because it is not needed.
    def apply_override!(override, base, total_value, cards, secret_cards)
      # Keep track of whether this override already existed before this method ran.
      # This matters because deleting an old override still counts as a change.
      was_persisted = override.persisted?

      # Only store total_value if it is different from the JSON baseline.
      # If it is the same, store nil so the app falls back to config/sets.json.
      override.total_value = same_decimal?(total_value, base[:total_value]) ? nil : total_value

      # Only store cards if it is different from the JSON baseline.
      override.cards = cards.to_i == base[:cards].to_i ? nil : cards.to_i

      # Only store secret_cards if it is different from the JSON baseline.
      override.secret_cards = secret_cards.to_i == base[:secret_cards].to_i ? nil : secret_cards.to_i

      # If there are no override values left, delete the override row.
      # This keeps the database clean and avoids storing unnecessary duplicate data.
      if override.total_value.nil? && override.cards.nil? && override.secret_cards.nil?
        override.destroy! if override.persisted?
        return was_persisted
      end

      # Check whether the override is new or has actual changes.
      changed = override.changed? || !override.persisted?

      # Save the override only if something changed.
      override.save! if changed

      # Return true or false so update_values can count the changed sets.
      changed
    end

    # This decides whether to use a submitted form value or the original JSON baseline.
    # If the admin leaves the field blank, the baseline is kept.
    def value_or_baseline(value, baseline, type)
      # Clean the submitted value.
      raw = value.to_s.strip

      # Blank input means keep the baseline value.
      return baseline if raw.blank?

      # Decimal is used for money/value fields.
      return decimal_param(raw, max: 1_000_000_000) if type == :decimal

      # Integer is used for card counts and secret card counts.
      integer_param(raw)
    end

    # This finds the best image to show for a set on the admin page.
    # It checks the app/assets/images/sets folder and falls back to the PokéValue logo if needed.
    def set_image(set)
      # Folder where set images are stored.
      folder = Rails.root.join("app", "assets", "images", "sets")

      # First option: use the slug as the file name.
      # Example: surging-sparks.png
      slug_file = "#{set["slug"]}.png"

      # Second option: use the box image file from the JSON data.
      box_file = File.basename(set["boxImage"].to_s)

      # Third option: use the logo file from the JSON data.
      logo_file = File.basename(set["logo"].to_s)

      # Use the slug image if it exists.
      return safe_asset_path("sets/#{slug_file}") if File.exist?(folder.join(slug_file))

      # If no slug image exists, try the box image.
      return safe_asset_path("sets/#{box_file}") if box_file.present? && File.exist?(folder.join(box_file))

      # If no box image exists, try the logo image.
      return safe_asset_path("sets/#{logo_file}") if logo_file.present? && File.exist?(folder.join(logo_file))

      # Final fallback so the admin page still has an image even when the set image is missing.
      safe_asset_path("pokevaluelogo.png")
    end

    # This safely converts a JSON decimal value into BigDecimal.
    # It returns nil if the value is blank or invalid.
    def decimal_or_nil(value)
      return nil if value.to_s.strip.blank?

      BigDecimal(value.to_s)
    rescue
      nil
    end

    # This compares two decimal values properly.
    # It avoids problems where the same number may be written differently as text.
    # Example: "10.0" and "10.00" should be treated as the same value.
    def same_decimal?(left, right)
      return true if left.nil? && right.nil?
      return false if left.nil? || right.nil?

      BigDecimal(left.to_s) == BigDecimal(right.to_s)
    rescue
      # If BigDecimal comparison fails for any reason, fall back to string comparison.
      left.to_s == right.to_s
    end

    # These are fallback baseline values.
    # They are used if a set is missing from config/sets.json or does not have values available.
    def empty_baseline
      { total_value: nil, cards: 0, secret_cards: 0 }
    end
  end
end
