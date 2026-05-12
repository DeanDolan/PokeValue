require "test_helper"

class ProductSearchTest < ActiveSupport::TestCase
  test "product search text is normalised" do
    result = Product.normalize_text("  Surging   Sparks BOOSTER Box  ")

    assert_equal "surging sparks booster box", result
  end

  test "product route type is normalised" do
    result = Product.normalize_type("Booster-Box Display")

    assert_equal "booster_box_display", result
  end

  test "product value override sku is built correctly" do
    result = Product.value_override_sku(
      set_slug: "surging sparks",
      route_type: "booster box"
    )

    assert_equal "surging-sparks--booster-box", result
  end
end
