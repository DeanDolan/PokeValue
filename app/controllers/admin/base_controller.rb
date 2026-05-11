module Admin
  class BaseController < ApplicationController
    include Authentication

    # This runs before any admin controller action.
    # Basically, before an admin page loads, Rails checks if the user is actually an admin.
    before_action :require_admin!

    private

    # This is the admin gatekeeper method.
    # Any controller that inherits from this BaseController will use this check.
    # If the user is signed in as an admin, the method stops here and lets them continue.
    # If they are not an admin, they get sent back to the homepage.
    def require_admin!
      return if respond_to?(:admin_signed_in?) && admin_signed_in?

      redirect_to root_path, alert: "Not authorized.", status: :see_other
    end

    # Rails params are not always a normal Ruby hash.
    # Sometimes they are ActionController::Parameters, which has extra Rails security behaviour.
    # This method converts them into a plain hash when needed.
    # I use this so admin update forms can be handled more easily.
    def param_hash(value)
      return value.to_unsafe_h if value.is_a?(ActionController::Parameters)
      return value if value.is_a?(Hash)

      {}
    end

    # This reads the main product/set data from config/sets.json.
    # That JSON file stores the catalogue information used around the app.
    # The encoding part helps avoid issues if the file has a BOM at the start.
    # If anything goes wrong while reading the file, it returns an empty hash instead of crashing the admin page.
    def sets_data
      JSON.parse(File.read(Rails.root.join("config", "sets.json"), encoding: "bom|utf-8"))
    rescue
      {}
    end

    # This safely converts a value from a form into a BigDecimal.
    # BigDecimal is better than normal floats for money/value fields because it is more accurate.
    # It blocks negative numbers because an admin should not be able to set a product value below 0.
    # It also blocks values above the max limit passed into the method.
    # If the value is invalid, too high, negative, or not a number, Rails raises a BadRequest error.
    def decimal_param(value, max:)
      decimal = BigDecimal(value.to_s.strip)
      raise ActionController::BadRequest if decimal.negative?
      raise ActionController::BadRequest if decimal > max

      decimal
    rescue
      raise ActionController::BadRequest
    end

    # This safely converts a value from a form into an integer.
    # This is useful for whole number fields, like quantities or counts.
    # It also blocks negative numbers so bad admin input cannot be saved.
    # If the value cannot be converted into a valid integer, it raises a BadRequest error.
    def integer_param(value)
      number = Integer(value.to_s.strip)
      raise ActionController::BadRequest if number.negative?

      number
    rescue
      raise ActionController::BadRequest
    end

    # This is used when the app wants to redirect the admin back to a previous page.
    # It only allows internal paths that start with one slash.
    # This stops unsafe redirects to outside websites.
    # If the path is blank or unsafe, it uses the fallback path instead.
    def safe_return_to(path, fallback:)
      value = path.to_s
      return fallback if value.blank?
      return fallback unless value.start_with?("/")
      return fallback if value.start_with?("//")

      value
    end

    # This tries to return the correct Rails asset path for an image or file.
    # If Rails cannot find the asset normally, it falls back to /assets/path.
    # This helps avoid the admin page breaking just because an asset lookup fails.
    def safe_asset_path(path)
      ActionController::Base.helpers.asset_path(path)
    rescue
      "/assets/#{path}"
    end

    # This turns a release date into a sortable number.
    # Julian day numbers are useful because older dates have lower numbers and newer dates have higher numbers.
    # If the date is missing or invalid, it returns 0 so sorting still works.
    def date_key(value)
      Date.parse(value.to_s).jd
    rescue
      0
    end

    # This shows dates in day/month/year format.
    # Example: 2026-05-13 becomes 13/05/2026.
    # If the date cannot be parsed, it just shows the original value as text.
    def display_date(value)
      Date.parse(value.to_s).strftime("%d/%m/%Y")
    rescue
      value.to_s
    end
  end
end
