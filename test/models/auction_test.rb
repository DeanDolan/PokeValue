require "test_helper"

class AuctionTest < ActiveSupport::TestCase
  test "auction accepts valid details" do
    seller = create_user("auctionseller1")

    auction = Auction.new(
      seller: seller,
      auction_description: "Sealed booster box auction",
      condition: "sealed",
      reserve_status: "No Reserve",
      status: "running",
      ends_at: 1.hour.from_now,
      auction_length_label: "1 hour",
      auction_length_seconds: 3600
    )

    assert auction.valid?
  end

  test "auction rejects missing required details" do
    auction = Auction.new

    assert_not auction.valid?
    assert auction.errors[:auction_description].any?
    assert auction.errors[:condition].any?
    assert auction.errors[:ends_at].any?
    assert auction.errors[:auction_length_label].any?
  end

  test "auction bid accepts valid bid details" do
    seller = create_user("auctionseller2")
    bidder = create_user("auctionbidder1")

    address = SavedAddress.create!(
      user: bidder,
      line1: "1 Test Street",
      city: "Dublin",
      country_code: "IE"
    )

    auction = Auction.create!(
      seller: seller,
      auction_description: "Sealed ETB auction",
      condition: "sealed",
      reserve_status: "No Reserve",
      status: "running",
      ends_at: 1.hour.from_now,
      auction_length_label: "1 hour",
      auction_length_seconds: 3600
    )

    bid = AuctionBid.new(
      auction: auction,
      bidder: bidder,
      saved_address: address,
      amount_cents: 5000
    )

    assert bid.valid?
  end

  private

  def create_user(username)
    User.create!(
      username: username,
      country_code: "IE",
      revolut_tag: "@#{username}",
      password: "StrongPass1!",
      password_confirmation: "StrongPass1!"
    )
  end
end
