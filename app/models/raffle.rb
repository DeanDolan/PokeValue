class Raffle < ApplicationRecord
  belongs_to :host, class_name: "User"
  belongs_to :winner_user, class_name: "User", optional: true
  belongs_to :main_raffle, class_name: "Raffle", optional: true

  has_many :mini_raffles, class_name: "Raffle", foreign_key: :main_raffle_id, dependent: :nullify
  has_many :raffle_tickets, dependent: :destroy
  has_many_attached :photos

  KINDS = %w[raffle mini].freeze
  STATUSES = %w[active completed incompleted].freeze

  validates :title, presence: true, length: { maximum: 120 }
  validates :raffle_kind, presence: true, inclusion: { in: KINDS }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :ticket_price_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :total_tickets, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 1000 }
  validates :revolut_tag, presence: true, length: { maximum: 80 }
  validate :photos_count_and_type
  validate :main_raffle_rules

  scope :newest_first, -> { order(created_at: :desc) }
  scope :active_only, -> { where(status: "active") }
  scope :completed_only, -> { where(status: "completed") }
  scope :incompleted_only, -> { where(status: "incompleted") }
  scope :main_raffles, -> { where(raffle_kind: "raffle") }
  scope :mini_raffles, -> { where(raffle_kind: "mini") }
  scope :running_main_raffles, -> { where(raffle_kind: "raffle", status: "active") }

  def active?
    status.to_s == "active"
  end

  def completed?
    status.to_s == "completed"
  end

  def incompleted?
    status.to_s == "incompleted"
  end

  def mini?
    raffle_kind.to_s == "mini"
  end

  def main?
    raffle_kind.to_s == "raffle"
  end

  def sold_tickets_count
    raffle_tickets.count
  end

  def tickets_left
    total_tickets.to_i - sold_tickets_count
  end

  def sold_out?
    total_tickets.to_i > 0 && tickets_left <= 0
  end

  def ticket_price_eur
    ticket_price_cents.to_i / 100.0
  end

  def taken_numbers
    raffle_tickets.order(:ticket_number).pluck(:ticket_number)
  end

  def available_numbers
    used = taken_numbers
    (1..total_tickets.to_i).to_a - used
  end

  def total_pot_cents
    raffle_tickets.sum(:amount_paid_cents)
  end

  def paid_amount_cents
    raffle_tickets.where(paid: true).sum(:amount_paid_cents)
  end

  def can_be_run_by?(user)
    return false unless user
    return false unless active?
    return false unless sold_out?
    host_id.to_i == user.id.to_i
  end

  def can_be_ended_by?(user)
    return false unless user
    return false unless active?
    host_id.to_i == user.id.to_i || user.admin?
  end

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

  def end_incomplete!
    update!(status: "incompleted", ended_at: Time.current)
  end

  private

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

  def photos_count_and_type
    return unless photos.attached?

    if photos.count > 4
      errors.add(:photos, "must be 4 images or fewer")
    end

    photos.each do |photo|
      content_type = photo.content_type.to_s
      next if content_type == "image/png" || content_type == "image/jpeg" || content_type == "image/jpg"

      errors.add(:photos, "must be JPG or PNG")
      break
    end
  end
end
