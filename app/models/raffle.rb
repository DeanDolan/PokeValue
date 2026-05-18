class Raffle < ApplicationRecord
  # Connects each raffle to the user who created or hosts it.
  belongs_to :host, class_name: "User"

  # Connects a completed raffle to the winning user when the winner is a registered user.
  belongs_to :winner_user, class_name: "User", optional: true

  # Connects a mini raffle to its main raffle when applicable.
  belongs_to :main_raffle, class_name: "Raffle", optional: true

  # Connects a main raffle to its linked mini raffles.
  has_many :mini_raffles, class_name: "Raffle", foreign_key: :main_raffle_id, dependent: :nullify

  # Connects each raffle to its bought or assigned tickets.
  has_many :raffle_tickets, dependent: :destroy

  # Allowed raffle types.
  KINDS = %w[raffle mini].freeze

  # Allowed raffle lifecycle states.
  STATUSES = %w[active completed incompleted].freeze

  # Requires a raffle title and limits its length.
  validates :title, presence: true, length: { maximum: 120 }

  # Requires the raffle type to be either a main raffle or mini raffle.
  validates :raffle_kind, presence: true, inclusion: { in: KINDS }

  # Requires the raffle status to match one of the allowed lifecycle states.
  validates :status, presence: true, inclusion: { in: STATUSES }

  # Requires the ticket price to be stored as a positive whole number in cents.
  validates :ticket_price_cents, numericality: { only_integer: true, greater_than: 0 }

  # Requires the raffle to have between 1 and 1000 tickets.
  validates :total_tickets, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 1000 }

  # Requires the host's Revolut tag for raffle payment handling.
  validates :revolut_tag, presence: true, length: { maximum: 80 }

  # Runs the custom rules for mini raffles and main raffles.
  validate :main_raffle_rules

  # Returns raffles from newest to oldest.
  scope :newest_first, -> { order(created_at: :desc) }

  # Returns only active raffles.
  scope :active_only, -> { where(status: "active") }

  # Returns only completed raffles.
  scope :completed_only, -> { where(status: "completed") }

  # Returns only incompleted raffles.
  scope :incompleted_only, -> { where(status: "incompleted") }

  # Returns only main raffles.
  scope :main_raffles, -> { where(raffle_kind: "raffle") }

  # Returns only mini raffles.
  scope :mini_raffles, -> { where(raffle_kind: "mini") }

  # Returns active main raffles that mini raffles can be linked to.
  scope :running_main_raffles, -> { where(raffle_kind: "raffle", status: "active") }

  # Checks whether the raffle is currently active.
  def active?
    status.to_s == "active"
  end

  # Checks whether the raffle has been completed.
  def completed?
    status.to_s == "completed"
  end

  # Checks whether the raffle has been ended without completion.
  def incompleted?
    status.to_s == "incompleted"
  end

  # Checks whether this raffle is a mini raffle.
  def mini?
    raffle_kind.to_s == "mini"
  end

  # Checks whether this raffle is a main raffle.
  def main?
    raffle_kind.to_s == "raffle"
  end

  # Counts how many tickets have been taken for this raffle.
  def sold_tickets_count
    raffle_tickets.count
  end

  # Calculates how many tickets are still available.
  def tickets_left
    total_tickets.to_i - sold_tickets_count
  end

  # Checks whether every ticket has been taken.
  def sold_out?
    total_tickets.to_i > 0 && tickets_left <= 0
  end

  # Converts the stored ticket price from cents into euros.
  def ticket_price_eur
    ticket_price_cents.to_i / 100.0
  end

  # Returns all ticket numbers already taken in this raffle.
  def taken_numbers
    raffle_tickets.order(:ticket_number).pluck(:ticket_number)
  end

  # Returns all ticket numbers that are still available.
  def available_numbers
    used = taken_numbers
    (1..total_tickets.to_i).to_a - used
  end

  # Calculates the total raffle pot in cents.
  def total_pot_cents
    raffle_tickets.sum(:amount_paid_cents)
  end

  # Calculates the amount marked as paid in cents.
  def paid_amount_cents
    raffle_tickets.where(paid: true).sum(:amount_paid_cents)
  end

  # Checks whether the given user can run the raffle.
  def can_be_run_by?(user)
    return false unless user
    return false unless active?
    return false unless sold_out?

    host_id.to_i == user.id.to_i
  end

  # Checks whether the given user can end the raffle.
  def can_be_ended_by?(user)
    return false unless user
    return false unless active?

    host_id.to_i == user.id.to_i || user.admin?
  end

  # Runs the raffle and randomly selects one winning ticket.
  def run!
    raise ActiveRecord::RecordInvalid, self unless sold_out? && active?

    winning_ticket = raffle_tickets.order(Arel.sql("RANDOM()")).first
    raise ActiveRecord::RecordInvalid, self if winning_ticket.blank?

    update!(
      status: "completed",
      winner_number: winning_ticket.ticket_number,
      winner_name: winning_ticket.display_name,
      winner_user_id: winning_ticket.user_id,
      completed_at: Time.current
    )

    winning_ticket
  end

  private

  # Checks that mini raffles are linked to a valid active main raffle.
  def main_raffle_rules
    if mini?
      if main_raffle_id.blank?
        errors.add(:main_raffle_id, "must be selected for a mini raffle")
        return
      end

      if main_raffle.blank?
        errors.add(:main_raffle_id, "is invalid")
        return
      end

      if main_raffle_id == id
        errors.add(:main_raffle_id, "cannot be the same raffle")
      end

      if main_raffle.raffle_kind != "raffle"
        errors.add(:main_raffle_id, "must be a main raffle")
      end

      if main_raffle.status != "active"
        errors.add(:main_raffle_id, "must be an active main raffle")
      end
    else
      self.main_raffle_id = nil
    end
  end
end
