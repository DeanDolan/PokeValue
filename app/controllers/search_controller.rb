class SearchController < ApplicationController
  def index
    @q = params[:q].to_s.strip
  end
end
