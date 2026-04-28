class Auction < ApplicationRecord
  belongs_to :seller, class_name: "User"

  has_many :auction_bids, dependent: :destroy
  has_many_attached :photos

  STATUSES = %w[running ended payment_pending paid sold].freeze
  RESERVE_STATUSES = [ "Reserve", "No Reserve" ].freeze

  validates :auction_description, presence: true, length: { maximum: 250 }
  validates :condition, presence: true
  validates :reserve_status, presence: true, inclusion: { in: RESERVE_STATUSES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :ends_at, presence: true

  validates :auction_length_label, presence: true, if: -> { has_attribute?(:auction_length_label) }
  validates :auction_length_seconds, numericality: { greater_than: 0 }, if: -> {
    has_attribute?(:auction_length_seconds) && self[:auction_length_seconds].present?
  }

  validates :reserve_cents, numericality: { greater_than: 0 }, if: -> {
    reserve? && has_attribute?(:reserve_cents) && self[:reserve_cents].present?
  }

  validate :photos_count_and_type

  before_validation :normalize_fields

  def self.refresh_all_statuses!
    return unless table_exists?

    order(:id).find_each do |auction|
      auction.refresh_status_and_settle!
    rescue
    end
  end

  def reserve?
    reserve_status.to_s == "Reserve"
  end

  def no_reserve?
    reserve_status.to_s == "No Reserve"
  end

  def running?
    status.to_s == "running" && ends_at.present? && ends_at > Time.current
  end

  def ended?
    status.to_s == "ended"
  end

  def payment_pending?
    status.to_s == "payment_pending"
  end

  def paid?
    status.to_s == "paid"
  end

  def sold?
    status.to_s == "sold"
  end

  def current_bid_cents_value
    highest_bid&.amount_cents.to_i
  end

  def highest_bid
    auction_bids.order(amount_cents: :desc, created_at: :asc).first
  end

  def reserve_met?
    return true if no_reserve?
    return false if highest_bid.blank?

    highest_bid.amount_cents.to_i >= reserve_cents.to_i
  end

  def winning_bidder
    stored_id = has_attribute?(:winning_bidder_id) ? self[:winning_bidder_id] : nil
    bidder_id = stored_id.presence || highest_bid&.bidder_id
    return nil if bidder_id.blank?

    User.find_by(id: bidder_id)
  end

  def winning_address_text
    stored_text = has_attribute?(:winning_address_text) ? self[:winning_address_text].to_s : ""
    return stored_text if stored_text.present?

    bid = highest_bid
    bid ? address_text_for_bid(bid) : ""
  end

  def winner_revolut_tag
    if has_attribute?(:winner_revolut_tag_encrypted) && winner_revolut_tag_encrypted.present?
      return User.revolut_tag_encryptor.decrypt_and_verify(winner_revolut_tag_encrypted)
    end

    winning_bidder&.revolut_tag.to_s
  rescue
    ""
  end

  def host_revolut_tag
    seller&.revolut_tag.to_s
  rescue
    ""
  end

  def can_end_early_by?(user)
    return false unless user
    return false unless seller_id.to_i == user.id.to_i
    return false unless running?

    no_reserve? || !reserve_met?
  end

  def end_early!
    return self unless can_end_early_by?(seller)

    finalize_result!(ended_at: Time.current)
    reload
  end

  def refresh_status_and_settle!
    return self unless persisted?
    return self if sold?
    return self if paid?
    return self if payment_pending?
    return self if ended? && settled_at_value.present?

    if status.to_s == "running" && ends_at.present? && ends_at <= Time.current
      finalize_result!(ended_at: ends_at)
    elsif status.to_s == "ended" && settled_at_value.blank?
      settle_as_ended!(Time.current)
    end

    reload
  end

  def confirm_payment_by_winner!(user)
    return false unless user
    return false unless winning_bidder&.id.to_i == user.id.to_i
    return false unless payment_pending?

    attrs = {
      status: "paid",
      updated_at: Time.current
    }

    attrs[:payment_confirmed_at] = Time.current if has_attribute?(:payment_confirmed_at)

    if has_attribute?(:winner_revolut_tag_encrypted) && user.respond_to?(:revolut_tag) && user.revolut_tag.present?
      attrs[:winner_revolut_tag_encrypted] = User.revolut_tag_encryptor.encrypt_and_sign(user.revolut_tag)
    end

    update_columns(attrs)
    true
  rescue
    false
  end

  def verify_payment_by_seller!(user)
    return false unless user
    return false unless seller_id.to_i == user.id.to_i
    return false unless paid?

    attrs = {
      status: "sold",
      updated_at: Time.current
    }

    attrs[:payment_verified_at] = Time.current if has_attribute?(:payment_verified_at)

    update_columns(attrs)
    true
  rescue
    false
  end

  private

  def normalize_fields
    self.auction_description = auction_description.to_s.strip
    self.status = status.to_s.presence || "running"
    self.reserve_status = reserve_status.to_s.presence || "No Reserve"
    self.condition = condition.to_s.presence
  end

  def settled_at_value
    has_attribute?(:settled_at) ? self[:settled_at] : nil
  end

  def finalize_result!(ended_at:)
    winning = highest_bid

    if winning.blank?
      settle_as_ended!(ended_at)
      return
    end

    if reserve? && winning.amount_cents.to_i < reserve_cents.to_i
      settle_as_ended!(ended_at)
      return
    end

    settle_as_payment_pending!(winning, ended_at)
  end

  def settle_as_ended!(ended_at)
    return self if ended? && settled_at_value.present?

    safe_write_columns(
      status: "ended",
      settled_at: settled_at_value || Time.current,
      ends_at: normalized_end_time(ended_at)
    )

    self
  end

  def settle_as_payment_pending!(winning_bid, ended_at)
    return self if payment_pending? || paid? || sold?

    attrs = {
      status: "payment_pending",
      settled_at: settled_at_value || Time.current,
      ends_at: normalized_end_time(ended_at),
      winning_bid_cents: winning_bid.amount_cents.to_i,
      winning_bidder_id: winning_bid.bidder_id,
      winning_address_text: address_text_for_bid(winning_bid)
    }

    attrs[:winning_saved_address_id] = winning_bid.saved_address_id if has_attribute?(:winning_saved_address_id)

    safe_write_columns(attrs)

    self
  end

  def address_text_for_bid(bid)
    address = bid.respond_to?(:saved_address) ? bid.saved_address : nil
    return "" if address.blank?

    if address.respond_to?(:single_line)
      address.single_line.to_s
    else
      [ address.try(:line1), address.try(:line2).presence, address.try(:city), address.try(:county).presence, address.try(:postcode).presence, address.try(:country_code) ].compact.join(", ")
    end
  end

  def normalized_end_time(value)
    [ ends_at, value, Time.current ].compact.min
  end

  def safe_write_columns(attrs)
    allowed = self.class.column_names.map(&:to_sym)
    filtered = attrs.select { |key, _| allowed.include?(key.to_sym) }
    filtered[:updated_at] = Time.current if allowed.include?(:updated_at) && !filtered.key?(:updated_at)
    return if filtered.empty?

    update_columns(filtered)
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
