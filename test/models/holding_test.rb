require "test_helper"

class HoldingTest < ActiveSupport::TestCase
  test "normal condition uses full value" do
    value = Holding.adjusted_value_for_condition("100.00", "sealed")

    assert_equal BigDecimal("100.00"), value
  end

  test "loosely sealed condition applies ten percent reduction" do
    value = Holding.adjusted_value_for_condition("100.00", "loosely sealed")

    assert_equal BigDecimal("90.00"), value
  end

  test "unsealed condition returns base value" do
    value = Holding.adjusted_value_for_condition("100.00", "unsealed")

    assert_equal BigDecimal("100.00"), value
  end

  test "invalid base value returns zero" do
    value = Holding.adjusted_value_for_condition("invalid", "sealed")

    assert_equal BigDecimal("0"), value
  end

  test "holding portfolio amounts are recalculated correctly" do
    holding = Holding.new(
      quantity: 2,
      cost_per_unit: "50.00",
      value: "100.00",
      condition: "sealed"
    )

    result = Product.recalculate_holding_amounts(holding)

    assert_equal BigDecimal("100.00"), result[:value]
    assert_equal BigDecimal("100.00"), result[:total_cost]
    assert_equal BigDecimal("200.00"), result[:total_value]
    assert_equal BigDecimal("100.00"), result[:pl]
    assert_equal BigDecimal("100.00"), result[:roi_pct]
  end
end
