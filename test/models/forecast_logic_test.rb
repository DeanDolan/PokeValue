require "test_helper"

class ForecastLogicTest < ActiveSupport::TestCase
  test "forecast product variant is inferred" do
    controller = ForecastsController.new

    result = controller.send(:infer_variant_from_product_name, "Elite Trainer Box (Lucario)")

    assert_equal "Lucario", result
  end

  test "forecast product category is inferred" do
    controller = ForecastsController.new

    pc_etb_result = controller.send(:infer_category_from_product_name, "Pokemon Center Elite Trainer Box")
    booster_box_result = controller.send(:infer_category_from_product_name, "Surging Sparks Booster Box")

    assert_equal "PC ETB", pc_etb_result
    assert_equal "BBox", booster_box_result
  end

  test "forecast attempt queries are built" do
    controller = ForecastsController.new

    result = controller.send(
      :build_attempt_queries,
      set_name: "Surging Sparks",
      product_name: "Surging Sparks Booster Box",
      product_category: "BBox",
      product_variant: "",
      origin: ""
    )

    assert result.any?
    assert_includes result, {
      "set_name" => "Surging Sparks",
      "product_name" => "Surging Sparks Booster Box"
    }
  end
end
