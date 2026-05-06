module Admin
  class RafflesController < ApplicationController
    include Authentication

    before_action :require_admin

    def index
      @raffles = Raffle.includes(:host, :winner_user, :main_raffle, :raffle_tickets, photos_attachments: :blob).order(created_at: :desc).to_a
      @active_raffles = @raffles.select { |r| r.raffle_kind.to_s == "raffle" && r.status.to_s == "active" }
      @active_mini_raffles = @raffles.select { |r| r.raffle_kind.to_s == "mini" && r.status.to_s == "active" }
      @completed_raffles = @raffles.select { |r| r.status.to_s == "completed" }
      @incompleted_raffles = @raffles.select { |r| r.status.to_s == "incompleted" }
    end

    def destroy
      redirect_target = safe_return_path
      raffle = Raffle.find(params[:id])
      raffle.destroy!

      redirect_to redirect_target, notice: "Raffle deleted.", status: :see_other
    rescue
      redirect_to safe_return_path, alert: "Could not delete raffle.", status: :see_other
    end

    private

    def require_admin
      ok =
        if respond_to?(:admin_signed_in?)
          admin_signed_in?
        elsif respond_to?(:current_user) && current_user
          current_user.respond_to?(:admin?) ? current_user.admin? : false
        else
          false
        end

      redirect_to(root_path, alert: "Not authorized.", status: :see_other) unless ok
    end

    def safe_return_path
      return_to = params[:return_to].to_s

      if return_to.present? && return_to.start_with?("/") && !return_to.start_with?("//")
        return_to
      else
        admin_raffles_path
      end
    rescue
      admin_raffles_path
    end
  end
end
