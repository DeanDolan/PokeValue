module Admin
  class RafflesController < BaseController
    # This loads the admin raffles page.
    # The admin page separates raffles into active raffles, active mini raffles,
    # completed raffles and incompleted raffles.
    def index
      # Start with all raffles and preload the related data needed on the page.
      # includes helps avoid loading the host, winner, tickets and images one by one.
      # newest_first keeps the newest raffles near the top.
      scope = Raffle.includes(:host, :winner_user, :main_raffle, :raffle_tickets, photos_attachments: :blob).newest_first

      # Normal active raffles.
      # These are full raffles that are still open/running.
      @active_raffles = scope.where(raffle_kind: "raffle", status: "active").to_a

      # Active mini raffles.
      # These are smaller raffles connected to the raffle feature but stored with raffle_kind as "mini".
      @active_mini_raffles = scope.where(raffle_kind: "mini", status: "active").to_a

      # Completed raffles.
      # These are raffles that have finished and should have a winner/result.
      @completed_raffles = scope.where(status: "completed").to_a

      # Incompleted raffles.
      # These are raffles that were ended/deleted before being completed properly.
      @incompleted_raffles = scope.where(status: "incompleted").to_a
    end

    # This deletes a raffle from the admin raffles page.
    # It is an admin action, so it is handled inside the Admin namespace.
    def destroy
      # Find the raffle by the ID in the URL and delete it.
      # destroy! is used so Rails throws an error if the delete fails.
      Raffle.find(params[:id]).destroy!

      # After deleting, send the admin back to the page they came from.
      # safe_return_to makes sure the return path is safe and stays inside the app.
      # If no safe return path exists, it goes back to the admin raffles page.
      redirect_to safe_return_to(params[:return_to], fallback: admin_raffles_path), notice: "Raffle deleted.", status: :see_other
    rescue
      # If anything goes wrong while deleting, do not crash the page.
      # Send the admin back with an error message instead.
      redirect_to safe_return_to(params[:return_to], fallback: admin_raffles_path), alert: "Could not delete raffle.", status: :see_other
    end
  end
end
