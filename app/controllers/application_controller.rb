class ApplicationController < ActionController::Base
  # Loads shared login helper methods such as current_user and logged_in?
  include Authentication

  # Builds the EU country list before each controller action
  before_action :set_eu_countries

  # Blocks older browsers that do not support modern Rails browser features
  allow_browser versions: :modern

  # Refreshes browser-cached responses when importmap JavaScript files change
  stale_when_importmap_changes

  private

  # Stores EU country names, codes and flags for forms and profile displays
  def set_eu_countries
    @eu_countries = [
      { code: "AT", name: "Austria", flag: "🇦🇹" },
      { code: "BE", name: "Belgium", flag: "🇧🇪" },
      { code: "BG", name: "Bulgaria", flag: "🇧🇬" },
      { code: "HR", name: "Croatia", flag: "🇭🇷" },
      { code: "CY", name: "Cyprus", flag: "🇨🇾" },
      { code: "CZ", name: "Czechia", flag: "🇨🇿" },
      { code: "DK", name: "Denmark", flag: "🇩🇰" },
      { code: "EE", name: "Estonia", flag: "🇪🇪" },
      { code: "FI", name: "Finland", flag: "🇫🇮" },
      { code: "FR", name: "France", flag: "🇫🇷" },
      { code: "DE", name: "Germany", flag: "🇩🇪" },
      { code: "GR", name: "Greece", flag: "🇬🇷" },
      { code: "HU", name: "Hungary", flag: "🇭🇺" },
      { code: "IE", name: "Ireland", flag: "🇮🇪" },
      { code: "IT", name: "Italy", flag: "🇮🇹" },
      { code: "LV", name: "Latvia", flag: "🇱🇻" },
      { code: "LT", name: "Lithuania", flag: "🇱🇹" },
      { code: "LU", name: "Luxembourg", flag: "🇱🇺" },
      { code: "MT", name: "Malta", flag: "🇲🇹" },
      { code: "NL", name: "Netherlands", flag: "🇳🇱" },
      { code: "PL", name: "Poland", flag: "🇵🇱" },
      { code: "PT", name: "Portugal", flag: "🇵🇹" },
      { code: "RO", name: "Romania", flag: "🇷🇴" },
      { code: "SK", name: "Slovakia", flag: "🇸🇰" },
      { code: "SI", name: "Slovenia", flag: "🇸🇮" },
      { code: "ES", name: "Spain", flag: "🇪🇸" },
      { code: "SE", name: "Sweden", flag: "🇸🇪" }
    ]
  end
end
