module Admin # Groups this controller inside the admin namespace
  class BaseController < ApplicationController
    include Authentication # Gives this controller access to current_user, user_signed_in? and admin_signed_in?

    before_action :require_admin! # Runs the admin check before every admin controller action

    private

    # Checks that the current user is signed in as an admin before allowing admin actions.
    def require_admin!
      return if respond_to?(:admin_signed_in?) && admin_signed_in?

      redirect_to root_path, alert: "Not authorized.", status: :see_other
    end

    # Converts Rails parameters into a plain Ruby hash.
    def normal_hash(value)
      return value.to_unsafe_h if value.is_a?(ActionController::Parameters)
      return value if value.is_a?(Hash)

      {}
    end

    # Reads the set and product catalogue data from config/sets.json.
    def sets_data
      JSON.parse(File.read(Rails.root.join("config", "sets.json"), encoding: "bom|utf-8"))
    rescue
      {}
    end

    # Converts a submitted whole-number field into a safe integer.
    def integer_param(value)
      number = Integer(value.to_s.strip)
      raise ActionController::BadRequest if number.negative?

      number
    rescue
      raise ActionController::BadRequest
    end

    # Allows redirects only to safe internal app paths.
    def safe_return_to(path, fallback:)
      value = path.to_s
      return fallback if value.blank?
      return fallback unless value.start_with?("/")
      return fallback if value.start_with?("//")

      value
    end

    # Returns a safe asset path with a fallback if Rails asset lookup fails.
    def safe_asset_path(path)
      ActionController::Base.helpers.asset_path(path)
    rescue
      "/assets/#{path}"
    end

    # Converts a date into a sortable Julian day number.
    def date_key(value)
      Date.parse(value.to_s).jd
    rescue
      0
    end

    # Formats a date as day/month/year for admin display.
    def display_date(value)
      Date.parse(value.to_s).strftime("%d/%m/%Y")
    rescue
      value.to_s
    end
  end
end
