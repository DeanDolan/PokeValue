module Admin
  class RafflesController < BaseController
    def index
      scope = Raffle.includes(:host, :winner_user, :main_raffle, :raffle_tickets, photos_attachments: :blob).newest_first

      @active_raffles = scope.where(raffle_kind: "raffle", status: "active").to_a
      @active_mini_raffles = scope.where(raffle_kind: "mini", status: "active").to_a
      @completed_raffles = scope.where(status: "completed").to_a
      @incompleted_raffles = scope.where(status: "incompleted").to_a
    end

    # Deletes a raffle from the admin page.
    def destroy
      Raffle.find(params[:id]).destroy!

      redirect_to safe_return_to(params[:return_to], fallback: admin_raffles_path), notice: "Raffle deleted.", status: :see_other
    rescue
      redirect_to safe_return_to(params[:return_to], fallback: admin_raffles_path), alert: "Could not delete raffle.", status: :see_other
    end
  end
end
