class Product < ApplicationRecord
  # Keeps product records connected to portfolio holdings.
  has_many :holdings, dependent: :nullify

  # Each product needs a unique SKU so it can be found across the app.
  validates :sku, presence: true, uniqueness: true

  # Each product needs a display name for pages, listings and portfolio views.
  validates :name, presence: true

  # Gets the set part from a product SKU.
  def set_slug
    s = sku.to_s
    return s.split(":", 2).first if s.include?(":")
    return s.split("--", 2).first if s.include?("--")

    s
  end

  # Gets the product type part from a product SKU.
  def type_code
    s = sku.to_s
    return s.split(":", 2).last if s.include?(":")
    return s.split("--", 2).last if s.include?("--")

    ""
  end

  # Normalises text for matching products across pages, holdings and admin rows.
  def self.normalize_text(value)
    value.to_s.unicode_normalize(:nfkc).downcase.strip.gsub(/\s+/, " ")
  end

  # Normalises type codes so route types and database product types can be compared safely.
  def self.normalize_type(value)
    value.to_s.strip.downcase.tr("-", "_").gsub(/\s+/, "_")
  end

  # Checks whether a route type needs the product name included in the URL.
  def self.route_needs_product_slug?(value)
    [
      "collection_box",
      "tin",
      "mini_tin",
      "mini_tin_display",
      "booster_pack",
      "blister_pack",
      "blister_pack_display",
      "half_booster_box"
    ].include?(normalize_type(value))
  end

  # Gets the image filename from an image path.
  def self.image_file_key(value)
    value.to_s.split("?").first.split("/").last.to_s.downcase.strip
  rescue
    ""
  end

  # Checks whether two image paths point to the same image file.
  def self.same_image_file?(a, b)
    aa = a.to_s
    bb = b.to_s
    a_key = image_file_key(aa)
    b_key = image_file_key(bb)

    return false if a_key.blank? || b_key.blank?

    a_key == b_key || aa.downcase.include?(b_key) || bb.downcase.include?(a_key)
  rescue
    false
  end

  # Creates the same admin value SKU used by product pages and the admin products table.
  def self.value_override_sku(set_slug:, route_type:)
    a = set_slug.to_s.strip.gsub(/[^a-zA-Z0-9\-_]+/, "-").gsub(/\A-+|-+\z/, "")
    b = route_type.to_s.strip.gsub(/[^a-zA-Z0-9\-_]+/, "-").gsub(/\A-+|-+\z/, "")
    "#{a}--#{b}"
  end

  # Finds an admin product value using the same SKU patterns used across the application.
  def self.find_admin_value(set_slug:, route_type:, type_code: nil)
    candidates = []
    candidates << value_override_sku(set_slug: set_slug, route_type: route_type)
    candidates << "#{set_slug}:#{route_type}"

    if type_code.present? && !route_needs_product_slug?(type_code)
      candidates << value_override_sku(set_slug: set_slug, route_type: type_code)
      candidates << "#{set_slug}:#{type_code}"
    end

    where(sku: candidates.map(&:to_s)).order(updated_at: :desc).first
  end

  # Returns the estimated value for a product, falling back only when no admin value exists.
  def self.estimated_value(set_slug:, route_type:, type_code: nil, fallback: nil)
    product = find_admin_value(set_slug: set_slug, route_type: route_type, type_code: type_code)
    value = product&.value

    return BigDecimal(value.to_s) if value.present? && BigDecimal(value.to_s) >= 0

    return BigDecimal(fallback.to_s) if fallback.present?

    BigDecimal("0")
  rescue
    BigDecimal("0")
  end

  # Finds the matching Product row for a holding.
  def self.find_holding_product(holding)
    linked_product = holding.product if holding.respond_to?(:product) && holding.product.present?

    if linked_product.present?
      linked_name = normalize_text(linked_product.name)
      linked_type = normalize_text(linked_product.product_type)
      holding_name = normalize_text(holding.product_type)

      if same_image_file?(linked_product.image, holding.image) || linked_name == holding_name || (!route_needs_product_slug?(linked_type) && linked_type == holding_name)
        return linked_product
      end
    end

    set_name = normalize_text(holding.set_name)
    product_type = normalize_text(holding.product_type)

    return nil if set_name.blank? || product_type.blank?

    candidates = Product.where("lower(set_name) = ?", set_name)

    image_match =
      candidates.find do |product|
        same_image_file?(product.image, holding.image)
      end

    return image_match if image_match

    exact_name =
      candidates.find do |product|
        normalize_text(product.name) == product_type
      end

    return exact_name if exact_name

    exact_type_matches =
      candidates.select do |product|
        normalize_text(product.product_type) == product_type
      end

    return exact_type_matches.first if exact_type_matches.length == 1

    candidates.find do |product|
      product_name = normalize_text(product.name)
      product_type.include?(product_name) ||
        product_name.include?(product_type)
    end
  rescue
    nil
  end

  # Calculates the portfolio value for a holding using the latest admin estimated value.
  def self.holding_value(holding)
    product = find_holding_product(holding)
    base_value = product&.value || holding.value || 0

    if defined?(Holding)
      Holding.adjusted_value_for_condition(base_value, holding.condition)
    else
      BigDecimal(base_value.to_s)
    end
  rescue
    BigDecimal("0")
  end

  # Calculates one holding's value, total value, profit/loss and ROI.
  def self.calculate_holding_totals(holding)
    quantity = holding.quantity.to_i
    quantity = 0 if quantity.negative?

    value = holding_value(holding)
    cost_per_unit = BigDecimal(holding.cost_per_unit.to_s)
    total_cost = (cost_per_unit * quantity).round(2)
    total_value = (value * quantity).round(2)
    pl = (total_value - total_cost).round(2)
    roi = total_cost.zero? ? BigDecimal("0") : ((pl / total_cost) * 100).round(2)

    {
      value: value.round(2),
      total_cost: total_cost,
      total_value: total_value,
      pl: pl,
      roi_pct: roi
    }
  rescue
    {
      value: BigDecimal("0"),
      total_cost: BigDecimal("0"),
      total_value: BigDecimal("0"),
      pl: BigDecimal("0"),
      roi_pct: BigDecimal("0")
    }
  end

  # Updates one holding in memory so portfolio tables immediately show live values.
  def self.update_holding_totals(holding)
    attrs = calculate_holding_totals(holding)

    holding.value = attrs[:value]
    holding.total_cost = attrs[:total_cost]
    holding.total_value = attrs[:total_value]
    holding.pl = attrs[:pl]
    holding.roi_pct = attrs[:roi_pct]

    holding
  end

  # Finds holdings connected to a product and saves their recalculated values.
  def self.update_holdings!(product)
    return unless defined?(Holding)
    return if product.blank?

    ids = []

    if product.persisted?
      ids += Holding.where(product_id: product.id).pluck(:id)
    end

    if product.set_name.present?
      product_name = product.name.to_s
      product_type = product.product_type.to_s

      if product_name.present?
        ids += Holding.where(set_name: product.set_name, product_type: product_name).pluck(:id)
      end

      if product_type.present? && !route_needs_product_slug?(product_type)
        ids += Holding.where(set_name: product.set_name, product_type: product_type).pluck(:id)
      end

      if product.image.present?
        Holding.where(set_name: product.set_name).find_each do |holding|
          next unless same_image_file?(product.image, holding.image)

          holding_name = normalize_text(holding.product_type)
          product_name_match = product_name.present? && holding_name == normalize_text(product_name)
          product_type_match = product_type.present? && holding_name == normalize_text(product_type)

          ids << holding.id if product_name_match || product_type_match || route_needs_product_slug?(product_type)
        end
      end
    end

    Holding.where(id: ids.uniq).find_each do |holding|
      attrs = calculate_holding_totals(holding)
      attrs[:updated_at] = Time.current if holding.has_attribute?(:updated_at)
      holding.update_columns(attrs)
    end
  end

  # Updates a list of holdings in memory for portfolio display and metrics.
  def self.update_all_holding_totals(holdings)
    Array(holdings).each do |holding|
      update_holding_totals(holding)
    end
  end
end
