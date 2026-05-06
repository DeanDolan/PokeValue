class RafflesController < ApplicationController
  before_action :require_login, only: [ :new, :create, :purchase_tickets, :return_tickets, :toggle_paid, :verify_payment, :run_raffle, :end_raffle, :destroy ]
  before_action :set_raffle, only: [ :show, :purchase_tickets, :return_tickets, :toggle_paid, :verify_payment, :run_raffle, :end_raffle, :destroy ]

  def index
    @raffle_filters = {
      q: params[:q].to_s.strip,
      min_ticket_price: params[:min_ticket_price].to_s.strip,
      max_ticket_price: params[:max_ticket_price].to_s.strip,
      min_tickets: params[:min_tickets].to_s.strip,
      max_tickets: params[:max_tickets].to_s.strip,
      ticket_status: params[:ticket_status].to_s.strip
    }

    @admin_can_manage_raffles = raffle_admin_user?

    @raffles = apply_raffle_filters(
      Raffle.includes(:host, :winner_user, :main_raffle, :raffle_tickets, photos_attachments: :blob).newest_first
    )

    @active_raffles = @raffles.select { |r| r.raffle_kind == "raffle" && r.status == "active" }
    @active_mini_raffles = @raffles.select { |r| r.raffle_kind == "mini" && r.status == "active" }
    @completed_raffles = @raffles.select { |r| r.status == "completed" }
    @incompleted_raffles = @raffles.select { |r| r.status == "incompleted" }
  end

  def new
    @raffle = Raffle.new(
      raffle_kind: "raffle",
      status: "active",
      total_tickets: 10,
      revolut_tag: current_user.revolut_tag.to_s
    )

    @running_main_raffles = Raffle.includes(:host).running_main_raffles.order(created_at: :desc)
  end

  def create
    host_revolut_tag = current_user.revolut_tag.to_s.strip

    if host_revolut_tag.blank?
      redirect_to new_raffle_path,
                  alert: "Your account does not have a Revolut Tag saved. You need a Revolut Tag before hosting a raffle.",
                  status: :see_other
      return
    end

    @raffle = Raffle.new(
      host: current_user,
      title: raffle_params[:title].to_s.strip,
      raffle_kind: raffle_params[:raffle_kind].to_s,
      main_raffle_id: raffle_params[:main_raffle_id].presence,
      ticket_price_cents: money_to_cents(ticket_price_param),
      total_tickets: raffle_params[:total_tickets].to_i,
      revolut_tag: host_revolut_tag,
      status: "active"
    )

    attach_photos(@raffle, raffle_params[:photos])

    if @raffle.save
      redirect_to raffle_path(@raffle), notice: "Raffle created successfully."
    else
      @running_main_raffles = Raffle.includes(:host).running_main_raffles.order(created_at: :desc)
      flash.now[:alert] = @raffle.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @admin_can_manage_raffles = raffle_admin_user?
    @tickets = @raffle.raffle_tickets.includes(:user).ordered
    @available_numbers = @raffle.available_numbers
    @my_tickets = current_user ? @tickets.select { |t| t.user_id.to_i == current_user.id.to_i } : []
    @host_view = current_user && @raffle.host_id.to_i == current_user.id.to_i
    @participant_rows = build_participant_rows(@tickets)
    @winning_ticket = @tickets.find { |t| t.ticket_number.to_i == @raffle.winner_number.to_i } if @raffle.completed?
    @paid_amount_cents = @tickets.select(&:paid?).sum(&:amount_paid_cents)

    @host_stats =
      if defined?(Review)
        avg = Review.where(seller_id: @raffle.host_id).average(:rating).to_f
        count = Review.where(seller_id: @raffle.host_id).count
        { avg: avg, count: count }
      else
        { avg: 0.0, count: 0 }
      end

    @reviews =
      if defined?(Review)
        Review.where(seller_id: @raffle.host_id).includes(:reviewer).order(created_at: :desc).limit(10).to_a
      else
        []
      end

    @viewer_is_raffle_winner =
      current_user.present? &&
      @raffle.completed? &&
      @raffle.winner_user_id.to_i == current_user.id.to_i &&
      @raffle.host_id.to_i != current_user.id.to_i

    @already_reviewed_host =
      if defined?(Review) && current_user
        Review.where(seller_id: @raffle.host_id, reviewer_id: current_user.id).exists?
      else
        false
      end

    @can_give_review = @viewer_is_raffle_winner && !@already_reviewed_host
  end

  def purchase_tickets
    return redirect_to raffle_path(@raffle), alert: "This raffle is no longer active." unless @raffle.active?

    buy_all = params[:buy_all_available].to_s == "1"
    numbers = Array(params[:ticket_numbers]).map(&:to_i).reject { |n| n <= 0 }.uniq.sort
    random_count = params[:random_quantity].to_i

    assign_name = params[:assigned_name].to_s.strip
    assign_reason = params[:assignment_reason].presence || params[:assign_reason].presence || params[:reason].presence
    assign_reason = assign_reason.to_s.strip

    if current_user.id == @raffle.host_id.to_i
      target_user_id = nil
      chosen_name = assign_name.presence
      return redirect_to raffle_path(@raffle), alert: "As host, type the name you want on the ticket." if chosen_name.blank?
      return redirect_to raffle_path(@raffle), alert: "Choose a reason." unless RaffleTicket::ASSIGNMENT_REASONS.include?(assign_reason)
    else
      target_user_id = current_user.id
      chosen_name = current_user.username.to_s
      assign_reason = nil
    end

    chosen_numbers =
      if buy_all
        @raffle.available_numbers
      elsif numbers.any?
        numbers
      elsif random_count > 0
        available = @raffle.available_numbers
        return redirect_to raffle_path(@raffle), alert: "Not enough tickets available." if random_count > available.size
        available.sample(random_count).sort
      else
        []
      end

    if chosen_numbers.empty?
      return redirect_to raffle_path(@raffle), alert: "Choose ticket numbers, choose buy all available, or enter a random quantity."
    end

    available_set = @raffle.available_numbers.to_set
    unless chosen_numbers.all? { |n| available_set.include?(n) }
      return redirect_to raffle_path(@raffle), alert: "One or more chosen ticket numbers are no longer available."
    end

    ActiveRecord::Base.transaction do
      chosen_numbers.each do |number|
        attrs = {
          user_id: target_user_id,
          assigned_name: chosen_name,
          ticket_number: number,
          paid: false,
          paid_at: nil,
          verified: false,
          verified_at: nil,
          revolut_tag: nil,
          amount_paid_cents: @raffle.ticket_price_cents.to_i
        }

        if RaffleTicket.column_names.include?("assignment_reason")
          attrs[:assignment_reason] = assign_reason
        elsif RaffleTicket.column_names.include?("assign_reason")
          attrs[:assign_reason] = assign_reason
        elsif RaffleTicket.column_names.include?("reason")
          attrs[:reason] = assign_reason
        end

        @raffle.raffle_tickets.create!(attrs)
      end
    end

    message =
      if current_user.id == @raffle.host_id.to_i
        "Tickets assigned successfully."
      else
        "Tickets purchased successfully. You do not need to pay for tickets until all tickets have been sold."
      end

    redirect_to raffle_path(@raffle), notice: message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to raffle_path(@raffle), alert: e.record.errors.full_messages.to_sentence.presence || e.message
  rescue StandardError => e
    redirect_to raffle_path(@raffle), alert: "Ticket assignment failed: #{e.message}"
  end

  def return_tickets
    return redirect_to raffle_path(@raffle), alert: "Tickets cannot be returned for this raffle." unless @raffle.active?

    ticket_numbers = Array(params[:ticket_numbers]).map(&:to_i).uniq
    return redirect_to raffle_path(@raffle), alert: "No tickets selected." if ticket_numbers.empty?

    tickets = @raffle.raffle_tickets.where(ticket_number: ticket_numbers)

    if tickets.empty?
      return redirect_to raffle_path(@raffle), alert: "No valid tickets found."
    end

    allowed =
      tickets.all? do |ticket|
        if current_user.id == @raffle.host_id.to_i
          true
        else
          ticket.user_id.to_i == current_user.id.to_i
        end
      end

    return redirect_to raffle_path(@raffle), alert: "You cannot return those tickets." unless allowed

    tickets.destroy_all
    redirect_to raffle_path(@raffle), notice: "Selected tickets were returned."
  end

  def toggle_paid
    return redirect_to raffle_path(@raffle), alert: "This raffle is no longer active." unless @raffle.active?

    tickets = @raffle.raffle_tickets.where(user_id: current_user.id)
    return redirect_to raffle_path(@raffle), alert: "You have no tickets in this raffle." if tickets.empty?

    new_paid = !tickets.all?(&:paid?)

    if new_paid
      revolut_tag = current_user.revolut_tag.to_s.strip

      if revolut_tag.blank?
        return redirect_to raffle_path(@raffle), alert: "Your account does not have a Revolut Tag saved. Please contact support or create a new account with a Revolut Tag."
      end

      tickets.update_all(
        paid: true,
        paid_at: Time.current,
        verified: false,
        verified_at: nil,
        revolut_tag: revolut_tag
      )

      redirect_to raffle_path(@raffle), notice: "Your tickets were marked as paid."
    else
      tickets.update_all(
        paid: false,
        paid_at: nil,
        verified: false,
        verified_at: nil
      )

      redirect_to raffle_path(@raffle), notice: "Your tickets were marked as unpaid."
    end
  end

  def verify_payment
    return redirect_to raffle_path(@raffle), alert: "Only the host can verify payments." unless current_user.id == @raffle.host_id.to_i

    user_id = params[:user_id].to_i
    display_name = params[:display_name].to_s.strip
    tickets =
      if user_id.positive?
        @raffle.raffle_tickets.where(user_id: user_id)
      else
        @raffle.raffle_tickets.where(user_id: nil, assigned_name: display_name)
      end

    return redirect_to raffle_path(@raffle), alert: "Entrant not found." if tickets.empty?

    new_verified = !tickets.all?(&:verified?)
    tickets.update_all(
      verified: new_verified,
      verified_at: (new_verified ? Time.current : nil)
    )

    redirect_to raffle_path(@raffle), notice: (new_verified ? "Payment verified." : "Payment unverified.")
  end

  def run_raffle
    unless @raffle.can_be_run_by?(current_user)
      return respond_to do |format|
        format.html { redirect_to raffle_path(@raffle), alert: "This raffle cannot be run yet." }
        format.json { render json: { ok: false, message: "This raffle cannot be run yet." }, status: :unprocessable_entity }
      end
    end

    winning_ticket = @raffle.run!

    respond_to do |format|
      format.html { redirect_to raffle_path(@raffle, auto_spin: 1), notice: "Raffle completed. Winning ticket: ##{winning_ticket.ticket_number}." }
      format.json do
        render json: {
          ok: true,
          raffle_id: @raffle.id,
          winning_number: winning_ticket.ticket_number,
          winning_name: winning_ticket.display_name,
          redirect_url: raffle_path(@raffle, auto_spin: 1)
        }
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    respond_to do |format|
      format.html { redirect_to raffle_path(@raffle), alert: e.record.errors.full_messages.to_sentence }
      format.json { render json: { ok: false, message: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity }
    end
  end

  def end_raffle
    unless @raffle.can_be_ended_by?(current_user)
      return redirect_to raffle_path(@raffle), alert: "This raffle cannot be ended."
    end

    move_raffle_to_incompleted!(@raffle)
    redirect_to raffles_path, notice: "Raffle ended and moved to Incompleted."
  end

  def destroy
    redirect_target = raffle_return_path

    if raffle_admin_user? && @raffle.host_id.to_i != current_user.id.to_i
      @raffle.destroy!
      return redirect_to redirect_target, notice: "Raffle deleted.", status: :see_other
    end

    unless @raffle.host_id.to_i == current_user.id.to_i
      return redirect_to redirect_target, alert: "You cannot delete this raffle.", status: :see_other
    end

    move_raffle_to_incompleted!(@raffle)
    redirect_to raffles_path, notice: "Raffle moved to Incompleted.", status: :see_other
  rescue
    redirect_to raffles_path, alert: "Could not delete raffle.", status: :see_other
  end

  private

  def apply_raffle_filters(scope)
    rows = scope.to_a

    q = params[:q].to_s.strip.downcase
    if q.present?
      rows = rows.select do |raffle|
        [
          raffle.title,
          raffle.host&.username,
          raffle.raffle_kind,
          raffle.status,
          raffle.main_raffle&.title
        ].join(" ").downcase.include?(q)
      end
    end

    min_ticket_price = money_to_cents(params[:min_ticket_price])
    if min_ticket_price.positive?
      rows = rows.select { |raffle| raffle.ticket_price_cents.to_i >= min_ticket_price }
    end

    max_ticket_price = money_to_cents(params[:max_ticket_price])
    if max_ticket_price.positive?
      rows = rows.select { |raffle| raffle.ticket_price_cents.to_i <= max_ticket_price }
    end

    min_tickets = params[:min_tickets].to_i
    if min_tickets.positive?
      rows = rows.select { |raffle| raffle.total_tickets.to_i >= min_tickets }
    end

    max_tickets = params[:max_tickets].to_i
    if max_tickets.positive?
      rows = rows.select { |raffle| raffle.total_tickets.to_i <= max_tickets }
    end

    case params[:ticket_status].to_s
    when "tickets_left"
      rows = rows.select { |raffle| raffle.tickets_left.to_i > 0 }
    when "sold_out"
      rows = rows.select(&:sold_out?)
    when "has_sold"
      rows = rows.select { |raffle| raffle.sold_tickets_count.to_i > 0 }
    end

    rows
  end

  def raffle_params
    params.require(:raffle).permit(:title, :raffle_kind, :main_raffle_id, :total_tickets, photos: [])
  end

  def ticket_price_param
    params[:ticket_price_eur].presence || params.dig(:raffle, :ticket_price_eur).presence || params.dig(:raffle, :ticket_price).presence
  end

  def set_raffle
    @raffle = Raffle.includes(:host, :winner_user, :main_raffle, :raffle_tickets, photos_attachments: :blob).find(params[:id])
  end

  def require_login
    redirect_to login_path unless current_user
  end

  def raffle_admin_user?
    ok = false

    begin
      ok = true if respond_to?(:admin_signed_in?) && admin_signed_in?
    rescue
    end

    return true if ok

    user = current_user
    return false unless user

    return true if user.respond_to?(:admin?) && user.admin?
    return true if user.respond_to?(:admin) && !!user.admin

    false
  rescue
    false
  end

  def raffle_return_path
    return_to = params[:return_to].to_s

    if return_to.present? && return_to.start_with?("/") && !return_to.start_with?("//")
      return_to
    else
      raffles_path
    end
  rescue
    raffles_path
  end

  def move_raffle_to_incompleted!(raffle)
    attrs = {
      status: "incompleted",
      updated_at: Time.current
    }

    attrs[:ended_at] = Time.current if Raffle.column_names.include?("ended_at")
    attrs[:completed_at] = nil if Raffle.column_names.include?("completed_at")
    attrs[:winner_number] = nil if Raffle.column_names.include?("winner_number")
    attrs[:winner_name] = nil if Raffle.column_names.include?("winner_name")
    attrs[:winner_user_id] = nil if Raffle.column_names.include?("winner_user_id")

    raffle.update_columns(attrs)
  end

  def attach_photos(record, photos)
    return unless record.respond_to?(:photos)
    return unless record.photos.respond_to?(:attach)

    Array(photos).reject(&:blank?).first(4).each do |photo|
      record.photos.attach(photo)
    end
  end

  def money_to_cents(value)
    return 0 if value.blank?

    (value.to_s.tr(",", ".").to_f * 100).round
  end

  def ticket_assignment_reason(ticket)
    if ticket.respond_to?(:assignment_reason)
      ticket.assignment_reason.to_s
    elsif ticket.respond_to?(:assign_reason)
      ticket.assign_reason.to_s
    elsif ticket.respond_to?(:reason)
      ticket.reason.to_s
    else
      ""
    end
  end

  def build_participant_rows(tickets)
    grouped = tickets.group_by { |ticket| [ ticket.user_id, ticket.display_name ] }

    grouped.map do |(user_id, display_name), rows|
      revolut_tags = rows.map(&:revolut_tag).map { |tag| tag.to_s.strip }.reject(&:blank?).uniq
      assignment_reasons = rows.map { |ticket| ticket_assignment_reason(ticket) }.map(&:strip).reject(&:blank?).uniq

      {
        user_id: user_id,
        display_name: display_name,
        ticket_count: rows.count,
        ticket_numbers: rows.map(&:ticket_number).sort,
        assignment_reason: assignment_reasons.first.to_s,
        paid_all: rows.all?(&:paid?),
        verified_all: rows.all?(&:verified?),
        paid_amount_cents: rows.select(&:paid?).sum(&:amount_paid_cents),
        total_amount_cents: rows.sum(&:amount_paid_cents),
        revolut_tag: revolut_tags.first.to_s
      }
    end.sort_by { |row| [ row[:display_name].to_s.downcase, row[:user_id].to_i ] }
  end
end
