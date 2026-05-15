class ApplicationController < ActionController::Base
  # Loads shared login helper methods such as current_user and logged_in?
  include Authentication

  # Blocks older browsers that do not support modern Rails browser features
  allow_browser versions: :modern

  # Refreshes browser-cached responses when importmap JavaScript files change
  stale_when_importmap_changes
end
