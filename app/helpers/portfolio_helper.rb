module PortfolioHelper
  def eur(amount)
    number_to_currency(amount.to_d, unit: "€", format: "%u%n", precision: 2)
  end

  def pct(value)
    "#{sprintf('%.2f', value.to_d)}%"
  end
end
