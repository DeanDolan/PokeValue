require "test_helper"

class MarketplaceListingTest < ActiveSupport::TestCase
  test "marketplace listing accepts valid listing details" do
    seller = create_user("selleruser1")

    listing = MarketplaceListing.new(
      seller: seller,
      status: "active",
      price_cents: 5000,
      quantity: 2,
      country_code: "IE",
      condition: "sealed",
      set_slug: "surging-sparks",
      route_type: "booster_box",
      product_sku: "surging-sparks--booster_box"
    )

    assert listing.valid?
  end

  test "marketplace listing rejects missing required fields" do
    seller = create_user("selleruser2")

    listing = MarketplaceListing.new(
      seller: seller,
      status: "active",
      price_cents: 5000,
      quantity: 2
    )

    assert_not listing.valid?
    assert listing.errors[:country_code].any?
    assert listing.errors[:condition].any?
    assert listing.errors[:set_slug].any?
    assert listing.errors[:route_type].any?
    assert listing.errors[:product_sku].any?
  end

  test "marketplace purchase converts cents into euro values" do
    purchase = MarketplacePurchase.new(
      unit_price_cents: 5000,
      total_price_cents: 10000,
      realised_pl_cents: 2500,
      seller_cost_per_unit_cents: 3750
    )

    assert_equal 50.0, purchase.unit_price_eur
    assert_equal 100.0, purchase.total_price_eur
    assert_equal 25.0, purchase.realised_pl_eur
    assert_equal 37.5, purchase.seller_cost_per_unit_eur
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
