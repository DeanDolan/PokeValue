class Holding < ApplicationRecord
  # Each holding belongs to one user and may link to one product record
  belongs_to :user
  belongs_to :product, optional: true

  validates :user_id, presence: true

  # Conditions that should not receive a normal market-value calculation
  NA_CONDITIONS = [
    "unsealed",
    "damaged",
    "box only",
    "contents only"
  ].freeze

  # Conditions valued at 90% of the base product value
  TEN_PERCENT_LESS = [
    "loosely sealed",
    "mini tear/hole (<2cm)",
    "mini tear/hole (1cm)",
    "pressure marks",
    "small imperfections"
  ].freeze

  # Conditions valued at 85% of the base product value
  FIFTEEN_PERCENT_LESS = [
    "big imperfections",
    "small tear",
    "small tear (>2cm)",
    "small tear (<1 inch)"
  ].freeze

  # Conditions valued at 80% of the base product value
  TWENTY_PERCENT_LESS = [
    "big tear",
    "big tear (>1 inch)",
    "big tear (>inch)",
    "slightly dented"
  ].freeze

  # Conditions valued at 70% of the base product value
  THIRTY_PERCENT_LESS = [
    "heavy dented"
  ].freeze

  # Normalises condition text before comparing it to condition lists
  def self.normalize_condition(condition)
    condition.to_s.strip.downcase.gsub(/\s+/, " ")
  end

  # Returns the value multiplier for the selected condition
  def self.condition_multiplier(condition)
    normalized = normalize_condition(condition)

    return nil if NA_CONDITIONS.include?(normalized)
    return 0.9 if TEN_PERCENT_LESS.include?(normalized)
    return 0.85 if FIFTEEN_PERCENT_LESS.include?(normalized)
    return 0.8 if TWENTY_PERCENT_LESS.include?(normalized)
    return 0.7 if THIRTY_PERCENT_LESS.include?(normalized)

    1.0
  end

  # Applies the condition multiplier to the base market value
  def self.adjusted_value_for_condition(base_value, condition)
    multiplier = condition_multiplier(condition)
    base = BigDecimal(base_value.to_s)

    return base.round(2) if multiplier.nil?

    (base * BigDecimal(multiplier.to_s)).round(2)
  rescue
    BigDecimal("0")
  end
end
