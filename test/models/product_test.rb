require "test_helper"

class ProductTest < ActiveSupport::TestCase
  test "product sku returns set slug and type code" do
    product = Product.new(
      sku: "surging-sparks--booster_box",
      name: "Surging Sparks Booster Box"
    )

    assert_equal "surging-sparks", product.set_slug
    assert_equal "booster_box", product.type_code
  end
end
