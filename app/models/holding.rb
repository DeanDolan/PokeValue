class Holding < ApplicationRecord
  belongs_to :user
  belongs_to :product, optional: true

  validates :user_id, presence: true

  NA_CONDITIONS = [
    "unsealed",
    "damaged",
    "box only",
    "contents only"
  ].freeze

  TEN_PERCENT_LESS = [
    "loosely sealed",
    "mini tear/hole (<2cm)",
    "mini tear/hole (1cm)",
    "pressure marks",
    "small imperfections"
  ].freeze

  FIFTEEN_PERCENT_LESS = [
    "big imperfections",
    "small tear (<1 inch)"
  ].freeze

  TWENTY_PERCENT_LESS = [
    "big tear (>1 inch)",
    "big tear (>inch)",
    "slightly dented"
  ].freeze

  THIRTY_PERCENT_LESS = [
    "heavy dented"
  ].freeze

  def self.normalize_condition(condition)
    condition.to_s.strip.downcase.gsub(/\s+/, " ")
  end

  def self.condition_multiplier(condition)
    normalized = normalize_condition(condition)

    return nil if NA_CONDITIONS.include?(normalized)
    return 0.9 if TEN_PERCENT_LESS.include?(normalized)
    return 0.85 if FIFTEEN_PERCENT_LESS.include?(normalized)
    return 0.8 if TWENTY_PERCENT_LESS.include?(normalized)
    return 0.7 if THIRTY_PERCENT_LESS.include?(normalized)

    1.0
  end

  def self.adjusted_value_for_condition(base_value, condition)
    multiplier = condition_multiplier(condition)
    base = BigDecimal(base_value.to_s)

    return base.round(2) if multiplier.nil?

    (base * BigDecimal(multiplier.to_s)).round(2)
  rescue
    BigDecimal("0")
  end
end
