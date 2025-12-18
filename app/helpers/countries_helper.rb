# References:
# - Rails view helpers:
#   https://guides.rubyonrails.org/action_view_helpers.html
# - Ruby Arrays / constants:
#   https://ruby-doc.org/core/Array.html
# - Basic Unicode handling in Ruby:
#   https://ruby-doc.org/core/String.html

module CountriesHelper
  # Static list of EU countries (27), using [name, ISO code]
  # I keep this frozen so it doesn't get modified accidentally at runtime.
  COUNTRIES = [
    [ "Austria",        "AT" ],
    [ "Belgium",        "BE" ],
    [ "Bulgaria",       "BG" ],
    [ "Croatia",        "HR" ],
    [ "Cyprus",         "CY" ],
    [ "Czechia",        "CZ" ],
    [ "Denmark",        "DK" ],
    [ "Estonia",        "EE" ],
    [ "Finland",        "FI" ],
    [ "France",         "FR" ],
    [ "Germany",        "DE" ],
    [ "Greece",         "GR" ],
    [ "Hungary",        "HU" ],
    [ "Ireland",        "IE" ],
    [ "Italy",          "IT" ],
    [ "Latvia",         "LV" ],
    [ "Lithuania",      "LT" ],
    [ "Luxembourg",     "LU" ],
    [ "Malta",          "MT" ],
    [ "Netherlands",    "NL" ],
    [ "Poland",         "PL" ],
    [ "Portugal",       "PT" ],
    [ "Romania",        "RO" ],
    [ "Slovakia",       "SK" ],
    [ "Slovenia",       "SI" ],
    [ "Spain",          "ES" ],
    [ "Sweden",         "SE" ]
  ].freeze

  # Turn a 2-letter country code into a flag emoji.
  # The trick is to convert each letter into the matching "regional indicator" codepoint.
  # Example: "IE" -> 🇮🇪
  def flag_emoji(code)
    code.to_s.upcase.chars
        .map { |c| (127397 + c.ord).chr(Encoding::UTF_8) }
        .join
  end
end
