module Admin
  class BaseController < ApplicationController
    include Authentication
    before_action :require_admin_mfa!
  end
end
