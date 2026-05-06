class AuctionBid < ApplicationRecord
  belongs_to :auction
  belongs_to :bidder, class_name: "User"
  belongs_to :saved_address

  # Reuses the bidder's previous address on later bids for the same auction.
  before_validation :inherit_previous_address

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validate :auction_must_be_running
  validate :bid_must_beat_previous_bid
  validate :address_must_be_present
  validate :address_must_belong_to_bidder

  # Updates the cached bids_count on the auction after a bid is created.
  after_commit :sync_auction_bid_count, on: :create

  private

  def inherit_previous_address
    return if saved_address_id.present?
    return unless auction && bidder_id.present?

    previous = auction.auction_bids.where(bidder_id: bidder_id).where.not(saved_address_id: nil).order(created_at: :desc).first
    self.saved_address = previous.saved_address if previous
  end

  def auction_must_be_running
    return if auction.blank?

    auction.refresh_status_and_settle!
    errors.add(:auction, "is no longer running") unless auction.running?
  end

  def bid_must_beat_previous_bid
    return if auction.blank?

    previous_cents = auction.current_bid_cents_value

    if amount_cents.to_i <= previous_cents.to_i
      errors.add(:amount_cents, "must be higher than the previous bid")
    end
  end

  def address_must_be_present
    errors.add(:saved_address, "must be selected for your first bid on this auction") if saved_address.blank?
  end

  def address_must_belong_to_bidder
    return if saved_address.blank? || bidder.blank?
    return if saved_address.user_id.to_i == bidder.id.to_i

    errors.add(:saved_address, "must belong to the bidder")
  end

  def sync_auction_bid_count
    auction.update_columns(bids_count: auction.auction_bids.count)
  end
end
