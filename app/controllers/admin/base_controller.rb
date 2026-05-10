module Admin
  class BaseController < ApplicationController
    include Authentication

    before_action :require_admin!

    private

    # Allows only signed-in admin users into admin controllers.
    def require_admin!
      return if respond_to?(:admin_signed_in?) && admin_signed_in?

      redirect_to root_path, alert: "Not authorized.", status: :see_other
    end

    # Converts Rails params into a plain Ruby hash.
    def param_hash(value)
      return value.to_unsafe_h if value.is_a?(ActionController::Parameters)
      return value if value.is_a?(Hash)

      {}
    end

    # Reads the sealed product and set catalogue from config/sets.json.
    def sets_data
      JSON.parse(File.read(Rails.root.join("config", "sets.json"), encoding: "bom|utf-8"))
    rescue
      {}
    end

    # Safely converts a value into BigDecimal and blocks unsafe admin values.
    def decimal_param(value, max:)
      decimal = BigDecimal(value.to_s.strip)
      raise ActionController::BadRequest if decimal.negative?
      raise ActionController::BadRequest if decimal > max

      decimal
    rescue
      raise ActionController::BadRequest
    end

    # Safely converts a value into an integer and blocks negative numbers.
    def integer_param(value)
      number = Integer(value.to_s.strip)
      raise ActionController::BadRequest if number.negative?

      number
    rescue
      raise ActionController::BadRequest
    end

    # Allows redirects only to internal paths.
    def safe_return_to(path, fallback:)
      value = path.to_s
      return fallback if value.blank?
      return fallback unless value.start_with?("/")
      return fallback if value.start_with?("//")

      value
    end

    # Returns an asset path, or falls back to the same logical path if asset lookup fails.
    def safe_asset_path(path)
      ActionController::Base.helpers.asset_path(path)
    rescue
      "/assets/#{path}"
    end

    # Turns a release date into a sortable number.
    def date_key(value)
      Date.parse(value.to_s).jd
    rescue
      0
    end

    # Shows dates in the same day/month/year format used on admin pages.
    def display_date(value)
      Date.parse(value.to_s).strftime("%d/%m/%Y")
    rescue
      value.to_s
    end
  end
end
