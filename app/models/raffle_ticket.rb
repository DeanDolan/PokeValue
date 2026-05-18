class RaffleTicket < ApplicationRecord
  # Host-assigned tickets must use one of these reasons.
  ASSIGNMENT_REASONS = [ "Mini Raffle", "Free Ticket(s)" ].freeze

  # Connects each ticket to one raffle.
  belongs_to :raffle

  # Connects the ticket to a user when it is bought by a registered user.
  belongs_to :user, optional: true

  # Makes sure the ticket number is a positive whole number.
  validates :ticket_number, numericality: { only_integer: true, greater_than: 0 }

  # Makes sure the paid amount is stored as a non-negative whole number in cents.
  validates :amount_paid_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Stops the same ticket number being used twice in the same raffle.
  validates :ticket_number, uniqueness: { scope: :raffle_id }

  # Limits the Revolut tag length but allows it to be empty.
  validates :revolut_tag, length: { maximum: 80 }, allow_blank: true

  # Allows only approved host-assignment reasons.
  validates :assignment_reason, inclusion: { in: ASSIGNMENT_REASONS }, allow_blank: true

  # Runs the custom ticket range check.
  validate :ticket_number_within_raffle_range

  # Runs the custom check that each ticket has a user or assigned name.
  validate :name_or_user_present

  # Returns tickets ordered by ticket number, then creation time.
  scope :ordered, -> { order(:ticket_number, :created_at) }

  # Checks whether this raffle ticket has been marked as paid.
  def paid?
    !!paid
  end

  # Checks whether this raffle ticket payment has been verified.
  def verified?
    !!verified
  end

  # Returns the display name shown for this raffle ticket.
  def display_name
    assigned_name.to_s.strip.presence || user&.username.to_s
  end

  private

  # Checks that the ticket number is inside the raffle's allowed ticket range.
  def ticket_number_within_raffle_range
    return if raffle.blank?
    return if ticket_number.to_i.between?(1, raffle.total_tickets.to_i)

    errors.add(:ticket_number, "must be between 1 and #{raffle.total_tickets}")
  end

  # Checks that a ticket has either a linked user or a manually assigned name.
  def name_or_user_present
    return if assigned_name.to_s.strip.present?
    return if user_id.present?

    errors.add(:base, "ticket must belong to a user or have an assigned name")
  end
end
