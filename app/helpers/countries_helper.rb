module CountriesHelper
  # Stores the supported EU countries as pairs.
  # First value = country name shown to the user.
  # Second value = two-letter country code saved in the database.
  COUNTRIES = [
    [ "Austria", "AT" ],
    [ "Belgium", "BE" ],
    [ "Bulgaria", "BG" ],
    [ "Croatia", "HR" ],
    [ "Cyprus", "CY" ],
    [ "Czechia", "CZ" ],
    [ "Denmark", "DK" ],
    [ "Estonia", "EE" ],
    [ "Finland", "FI" ],
    [ "France", "FR" ],
    [ "Germany", "DE" ],
    [ "Greece", "GR" ],
    [ "Hungary", "HU" ],
    [ "Ireland", "IE" ],
    [ "Italy", "IT" ],
    [ "Latvia", "LV" ],
    [ "Lithuania", "LT" ],
    [ "Luxembourg", "LU" ],
    [ "Malta", "MT" ],
    [ "Netherlands", "NL" ],
    [ "Poland", "PL" ],
    [ "Portugal", "PT" ],
    [ "Romania", "RO" ],
    [ "Slovakia", "SK" ],
    [ "Slovenia", "SI" ],
    [ "Spain", "ES" ],
    [ "Sweden", "SE" ]
  ].freeze

  # Builds the country dropdown data used by the registration form.
  # This is what makes eu_countries available inside registrations/_form.html.erb.
  def eu_countries
    COUNTRIES.map do |name, code|
      {
        code: code,
        name: name,
        flag: flag_emoji(code)
      }
    end
  end

  # Converts a two-letter country code into a flag emoji.
  # Example: "IE" becomes 🇮🇪.
  def flag_emoji(code)
    code.to_s.upcase.chars.map { |c| (127397 + c.ord).chr(Encoding::UTF_8) }.join
  end

  # Returns the full country name for an EU country code.
  # Example: "IE" becomes "Ireland".
  def country_name(code)
    c = code.to_s.upcase

    # Finds the matching country pair where the ISO code equals the given code.
    pair = COUNTRIES.find { |(_, iso)| iso == c }

    # If a matching country is found, return its name.
    # If no match is found, return the original code instead.
    pair ? pair[0] : c
  end
end
