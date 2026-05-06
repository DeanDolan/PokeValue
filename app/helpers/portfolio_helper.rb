module PortfolioHelper
  # Formats a number as euro currency for portfolio values
  def eur(amount)
    number_to_currency(amount.to_d, unit: "€", format: "%u%n", precision: 2)
  end

  # Formats a decimal value as a percentage string
  def pct(value)
    "#{sprintf('%.2f', value.to_d)}%"
  end
end
