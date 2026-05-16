class SetsController < ApplicationController
  require "json"
  require "date"

  # SETS.HTML.ERB
  # Eras shown in the sidebar filter when the user clicks the Sets navbar button.
  ERAS = [
    "Mega Evolution",
    "Scarlet & Violet",
    "Sword & Shield"
  ].freeze

  # SET.HTML.ERB
  # Product types that need the product name added into the URL so duplicate product types stay unique.
  PRODUCT_SLUG_TYPES = [
    "collection_box",
    "tin",
    "mini_tin",
    "mini_tin_display",
    "booster_pack",
    "blister_pack",
    "blister_pack_display",
    "half_booster_box"
  ].freeze

  # SET.HTML.ERB
  # Sets that are already treated as out of print on the individual set page urgency tile.
  OUT_OF_PRINT_NOW = [
    "scarlet & violet base",
    "paldea evolved",
    "obsidian flames",
    "151",
    "paradox rift",
    "paldean fates"
  ].freeze

  # SET.HTML.ERB
  # Estimated out-of-print dates used to calculate the countdown shown in the individual set page urgency tile.
  OUT_OF_PRINT_BY_DATE = {
    Date.new(2027, 4, 30) => [
      "temporal forces",
      "twilight masquerade",
      "shrouded fable",
      "stellar crown",
      "surging sparks",
      "prismatic evolutions"
    ],
    Date.new(2028, 4, 30) => [
      "journey together",
      "destined rivals",
      "black bolt",
      "white flare",
      "mega evolution base",
      "phantasmal flames",
      "ascended heroes"
    ],
    Date.new(2029, 4, 30) => [
      "perfect order"
    ]
  }.freeze

  # SETS.HTML.ERB
  # Runs when the user clicks the Sets navbar button and loads pages/sets.html.erb.
  def index
    @eras = ERAS
    @era_badges = era_badges

    @sets = sets_data.values.map do |set|
      {
        name: set["name"].to_s,
        era: set["era"].to_s,
        slug: set["slug"].to_s,
        image_url: set_card_image_url(set)
      }
    end

    render "pages/sets"
  end

  # SET.HTML.ERB
  # Runs when the user clicks a set card from sets.html.erb and loads pages/set.html.erb.
  def show
    set = find_set!(params[:slug])
    assign_set_details(set)
    apply_set_override

    @set_logo_url = set_logo_url(set)
    @urgency_label, @urgency_class, @urgency_subtitle = urgency_for_set(@set_name, @era, @release_date)
    @products = products_for_set(set)

    render "pages/set"
  end

  private

  # SHARED BY SETS.HTML.ERB AND SET.HTML.ERB
  # Loads all set and sealed product data from config/sets.json.
  def sets_data
    @sets_data ||= JSON.parse(File.read(Rails.root.join("config", "sets.json"), encoding: "bom|utf-8"))
  end

  # SETS.HTML.ERB
  # Sets the era badge images used on the main Sets page.
  def era_badges
    {
      "Mega Evolution" => asset_from_folder("sets", "megaevolution.png"),
      "Scarlet & Violet" => asset_from_folder("sets", "scarletandviolet.png"),
      "Sword & Shield" => asset_from_folder("sets", "swordandshield.png")
    }
  end

  # SETS.HTML.ERB
  # Gets the set image used on each card in the main Sets page grid.
  def set_card_image_url(set)
    asset_from_folder("sets", set["boxImage"])
  end

  # SET.HTML.ERB
  # Finds one set by slug after the user clicks a set card.
  def find_set!(slug)
    set = sets_data.values.find { |item| item["slug"].to_s == slug.to_s }
    raise ActiveRecord::RecordNotFound unless set

    set
  end

  # SET.HTML.ERB
  # Copies the selected set values into instance variables for the individual set page.
  def assign_set_details(set)
    @set_slug = set["slug"].to_s
    @set_name = set["name"].to_s
    @era = set["era"].to_s
    @release_date = set["releaseDate"].to_s
    @total_value = set["totalValue"] || set["total_value"]
    @cards = set["cards"] || set["totalCards"] || 0
    @secret = set["secretCards"] || set["secret_cards"] || 0
  end

  # SET.HTML.ERB ADMIN LOGIC
  # Applies admin-edited set values when a SetOverride row exists.
  def apply_set_override
    override = SetOverride.find_by(slug: @set_slug)

    return unless override

    @total_value = override.total_value if override.total_value.present?
    @cards = override.cards if override.cards.present?
    @secret = override.secret_cards if override.secret_cards.present?
  rescue
    nil
  end

  # SET.HTML.ERB
  # Returns the sealed products listed under the selected set in sets.json.
  def sealed_products(set)
    Array(set["sealed"] || [])
  end

  # SET.HTML.ERB
  # Builds product card data for the selected set page.
  def products_for_set(set)
    sealed_products(set).map do |product|
      type = product["type"].to_s
      name = product["name"].to_s

      {
        name: name,
        img_url: sealed_image_url(product),
        link: set_product_path(slug: @set_slug, type: route_type_for_product(type, name))
      }
    end
  end

  # SET.HTML.ERB
  # Gets the set logo used on the individual set page.
  def set_logo_url(set)
    asset_from_folder("sets", set["logo"])
  end

  # SET.HTML.ERB
  # Gets the sealed product image used on the individual set page.
  def sealed_image_url(product)
    asset_from_folder("sealed", product["img"])
  end

  # SHARED BY SETS.HTML.ERB AND SET.HTML.ERB
  # Finds an image inside app/assets/images and falls back to the PokeValue logo if missing.
  def asset_from_folder(folder, source)
    file = file_in_folder(folder, source)
    return view_context.asset_path("#{folder}/#{file}") if file

    view_context.asset_path("pokevaluelogo.png")
  end

  # SHARED BY SETS.HTML.ERB AND SET.HTML.ERB
  # Looks for an image file by exact filename first, then by case-insensitive filename.
  def file_in_folder(folder, source)
    file = File.basename(source.to_s)
    return nil if file.blank?

    path = Rails.root.join("app", "assets", "images", folder)
    exact = path.join(file)
    return file if File.file?(exact)

    files = asset_files(folder)
    files.find { |name| name.downcase == file.downcase }
  rescue
    nil
  end

  # SHARED BY SETS.HTML.ERB AND SET.HTML.ERB
  # Caches image filenames from each folder during the request.
  def asset_files(folder)
    @asset_files ||= {}
    @asset_files[folder] ||= Dir.children(Rails.root.join("app", "assets", "images", folder))
  rescue
    []
  end

  # SET.HTML.ERB
  # Calculates the text shown inside the urgency tile on the individual set page.
  def urgency_for_set(set_name, era, release_date)
    today = Date.current
    name = normalize_text(set_name)
    era_name = normalize_text(era)
    release = parse_date(release_date)

    out_date = out_of_print_date(name, era_name, release)
    out_now = era_name == "sword & shield" || OUT_OF_PRINT_NOW.include?(name)
    out_now = true if out_date && out_date <= today

    return [ "Out of Print", "urgency-black", nil ] if out_now
    return [ "Unknown", "urgency-unknown", nil ] unless out_date

    years, months, days = date_parts_between(today, out_date)

    [ "#{years} Years #{months} Months #{days} Days", "urgency-orange", "Until Out of Print" ]
  end

  # SET.HTML.ERB
  # Finds the fixed out-of-print date for a set or estimates one from the release year.
  def out_of_print_date(name, era_name, release_date)
    OUT_OF_PRINT_BY_DATE.each do |date, names|
      return date if names.include?(name)
    end

    return nil unless release_date
    return nil if era_name == "sword & shield" || OUT_OF_PRINT_NOW.include?(name)

    date = Date.new(release_date.year + 3, 4, 30)
    date <= release_date ? Date.new(release_date.year + 4, 4, 30) : date
  end

  # SET.HTML.ERB
  # Splits the time between two dates into years, months and days for the urgency tile.
  def date_parts_between(from_date, to_date)
    return [ 0, 0, 0 ] if to_date <= from_date

    years = to_date.year - from_date.year
    months = to_date.month - from_date.month
    days = to_date.day - from_date.day

    if days.negative?
      months -= 1
      previous_month = to_date.month - 1
      previous_year = to_date.year

      if previous_month.zero?
        previous_month = 12
        previous_year -= 1
      end

      days += Date.new(previous_year, previous_month, -1).day
    end

    if months.negative?
      years -= 1
      months += 12
    end

    [ years, months, days ]
  end

  # SET.HTML.ERB
  # Converts a date string from sets.json into a Date object for out-of-print calculations.
  def parse_date(value)
    Date.parse(value.to_s)
  rescue
    nil
  end

  # SET.HTML.ERB
  # Builds a product route type that can identify duplicate product types.
  def route_type_for_product(type, name)
    base = normalize_type(type)
    variant = extract_variant(name)
    pokemon_center_origin = detect_pokemon_center_origin(type, name)

    route = base.dup
    route << "--v-#{slugify(variant)}" if variant.present?
    route << "--o-#{slugify(pokemon_center_origin)}" if pokemon_center_origin.present?
    route << "--p-#{slugify(name)}" if PRODUCT_SLUG_TYPES.include?(base) && name.present?
    route
  end

  # SET.HTML.ERB
  # Extracts the bracketed variant from names like Elite Trainer Box (Lucario).
  def extract_variant(name)
    name.to_s[/\(([^)]+)\)/, 1].to_s.strip.presence
  end

  # SET.HTML.ERB
  # Checks whether a product is a Pokemon Center product.
  def detect_pokemon_center_origin(type, name)
    return "Pokemon Center" if normalize_type(type) == "pc_etb"
    return "Pokemon Center" if normalize_text(name).include?("pokemon center")

    nil
  end

  # SHARED BY SETS.HTML.ERB AND SET.HTML.ERB
  # Normalises text for matching set names, era names and product names.
  def normalize_text(value)
    value.to_s.unicode_normalize(:nfkc).downcase.strip.gsub(/\s+/, " ")
  end

  # SET.HTML.ERB
  # Normalises product type codes used in product routes and sets.json.
  def normalize_type(value)
    value.to_s.strip.downcase.tr("-", "_").gsub(/\s+/, "_")
  end

  # SET.HTML.ERB
  # Converts text into a safe URL slug for product links.
  def slugify(value)
    normalize_text(value).gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
  end
end
