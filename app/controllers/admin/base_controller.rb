module Admin
  class BaseController < ApplicationController
    include Authentication

    before_action :require_admin!

    private

    def require_admin!
      unless defined?(admin_signed_in?) && admin_signed_in?
        redirect_to login_path, alert: "Admin access required."
      end
    end
  end
end
