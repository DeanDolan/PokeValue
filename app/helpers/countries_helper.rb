module CountriesHelper
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

  def flag_emoji(code)
    code.to_s.upcase.chars.map { |c| (127397 + c.ord).chr(Encoding::UTF_8) }.join
  end

  def country_name(code)
    c = code.to_s.upcase
    pair = COUNTRIES.find { |(_, iso)| iso == c }
    pair ? pair[0] : c
  end
end
