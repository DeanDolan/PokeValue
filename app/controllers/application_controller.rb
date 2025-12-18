# References:
# - Rails controllers / callbacks:
#   https://guides.rubyonrails.org/action_controller_overview.html
# - Layouts, helpers, and controller-wide setup:
#   https://guides.rubyonrails.org/layouts_and_rendering.html
# - Importmap + caching behaviour:
#   https://github.com/rails/importmap-rails

class ApplicationController < ActionController::Base
  # Shared authentication helpers (current_user, logged_in?, etc.)
  include Authentication

  # Make the EU country list available on every request (used by registration form)
  before_action :set_eu_countries

  # Only allow modern browsers (comes from the browser-related helper)
  allow_browser versions: :modern

  # Let Rails know to treat responses as stale when the importmap changes
  stale_when_importmap_changes

  private

  # Keep a reusable list of EU countries + flags in one place
  # so I can use @eu_countries directly in views (e.g. registrations form).
  def set_eu_countries
    @eu_countries = [
      { code: "AT", name: "Austria",           flag: "🇦🇹" },
      { code: "BE", name: "Belgium",           flag: "🇧🇪" },
      { code: "BG", name: "Bulgaria",          flag: "🇧🇬" },
      { code: "HR", name: "Croatia",           flag: "🇭🇷" },
      { code: "CY", name: "Cyprus",            flag: "🇨🇾" },
      { code: "CZ", name: "Czechia",           flag: "🇨🇿" },
      { code: "DK", name: "Denmark",           flag: "🇩🇰" },
      { code: "EE", name: "Estonia",           flag: "🇪🇪" },
      { code: "FI", name: "Finland",           flag: "🇫🇮" },
      { code: "FR", name: "France",            flag: "🇫🇷" },
      { code: "DE", name: "Germany",           flag: "🇩🇪" },
      { code: "GR", name: "Greece",            flag: "🇬🇷" },
      { code: "HU", name: "Hungary",           flag: "🇭🇺" },
      { code: "IE", name: "Ireland",           flag: "🇮🇪" },
      { code: "IT", name: "Italy",             flag: "🇮🇹" },
      { code: "LV", name: "Latvia",            flag: "🇱🇻" },
      { code: "LT", name: "Lithuania",         flag: "🇱🇹" },
      { code: "LU", name: "Luxembourg",        flag: "🇱🇺" },
      { code: "MT", name: "Malta",             flag: "🇲🇹" },
      { code: "NL", name: "Netherlands",       flag: "🇳🇱" },
      { code: "PL", name: "Poland",            flag: "🇵🇱" },
      { code: "PT", name: "Portugal",          flag: "🇵🇹" },
      { code: "RO", name: "Romania",           flag: "🇷🇴" },
      { code: "SK", name: "Slovakia",          flag: "🇸🇰" },
      { code: "SI", name: "Slovenia",          flag: "🇸🇮" },
      { code: "ES", name: "Spain",             flag: "🇪🇸" },
      { code: "SE", name: "Sweden",            flag: "🇸🇪" }
    ]
  end
end
