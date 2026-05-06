class RaffleTicket < ApplicationRecord
  # Host-assigned tickets must use one of these reasons.
  ASSIGNMENT_REASONS = [ "Mini Raffle", "Free Ticket(s)" ].freeze

  belongs_to :raffle
  belongs_to :user, optional: true

  validates :ticket_number, numericality: { only_integer: true, greater_than: 0 }
  validates :amount_paid_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :ticket_number, uniqueness: { scope: :raffle_id }
  validates :revolut_tag, length: { maximum: 80 }, allow_blank: true
  validates :assignment_reason, inclusion: { in: ASSIGNMENT_REASONS }, allow_blank: true, if: :has_assignment_reason_column?
  validate :ticket_number_within_raffle_range
  validate :name_or_user_present

  scope :ordered, -> { order(:ticket_number, :created_at) }

  def paid?
    !!paid
  end

  def verified?
    !!verified
  end

  def display_name
    # Shows the assigned name first, otherwise falls back to the linked user's username.
    assigned_name.to_s.strip.presence || user&.username.to_s
  end

  def owner_can_manage?(actor)
    # The host can manage every ticket, while a participant can manage only their own ticket.
    return false unless actor
    return true if raffle.host_id.to_i == actor.id.to_i

    user_id.to_i == actor.id.to_i
  end

  private

  def has_assignment_reason_column?
    self.class.column_names.include?("assignment_reason")
  end

  def ticket_number_within_raffle_range
    return if raffle.blank?
    return if ticket_number.to_i.between?(1, raffle.total_tickets.to_i)

    errors.add(:ticket_number, "must be between 1 and #{raffle.total_tickets}")
  end

  def name_or_user_present
    # A ticket must either belong to a registered user or have a manually assigned display name.
    return if assigned_name.to_s.strip.present?
    return if user_id.present?

    errors.add(:base, "ticket must belong to a user or have an assigned name")
  end
end
