class HoldingsController < ApplicationController
  def create
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    attrs = holding_params
    quantity = attrs[:quantity].to_i
    quantity = 1 if quantity <= 0

    cost_per_unit = decimal_value(attrs[:cost_per_unit])
    base_value = decimal_value(attrs[:value])
    condition = attrs[:condition].to_s.strip
    adjusted_value = Holding.adjusted_value_for_condition(base_value, condition)

    product = find_or_create_product_for_holding(attrs, base_value)

    holding = Holding.new(
      user_id: current_user.id,
      product_id: product&.id,
      username: current_user.respond_to?(:username) ? current_user.username.to_s : nil,
      era: attrs[:era].to_s,
      set_name: attrs[:set_name].to_s,
      product_type: attrs[:product_type].to_s,
      condition: condition,
      quantity: quantity,
      listed_quantity: 0,
      cost_per_unit: cost_per_unit,
      value: adjusted_value,
      total_cost: cost_per_unit * quantity,
      total_value: adjusted_value * quantity,
      pl: (adjusted_value * quantity) - (cost_per_unit * quantity),
      roi_pct: roi_percent(cost_per_unit * quantity, (adjusted_value * quantity) - (cost_per_unit * quantity)),
      purchase_date: attrs[:purchase_date].presence || Date.current,
      image: attrs[:image_url].to_s
    )

    holding.save!

    create_summary_entry_safe(holding, "ADDED")

    redirect_back fallback_location: portfolio_path, notice: "Added to portfolio."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: portfolio_path, alert: e.record.errors.full_messages.to_sentence
  rescue
    redirect_back fallback_location: portfolio_path, alert: "Could not add product to portfolio."
  end

  def edit
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    @holding = Holding.where(user_id: current_user.id).find(params[:id])
  end

  def update
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    holding = Holding.where(user_id: current_user.id).find(params[:id])
    attrs = holding_params

    quantity = attrs[:quantity].presence || holding.quantity
    quantity = quantity.to_i
    quantity = 1 if quantity <= 0

    cost_per_unit =
      if attrs[:cost_per_unit].present?
        decimal_value(attrs[:cost_per_unit])
      else
        decimal_value(holding.cost_per_unit)
      end

    condition = attrs[:condition].presence || holding.condition.to_s

    base_value =
      if attrs[:value].present?
        decimal_value(attrs[:value])
      elsif holding.product && holding.product.respond_to?(:value) && holding.product.value.present?
        decimal_value(holding.product.value)
      else
        decimal_value(holding.value)
      end

    adjusted_value = Holding.adjusted_value_for_condition(base_value, condition)

    holding.update!(
      quantity: quantity,
      cost_per_unit: cost_per_unit,
      condition: condition,
      purchase_date: attrs[:purchase_date].presence || holding.purchase_date,
      value: adjusted_value,
      total_cost: cost_per_unit * quantity,
      total_value: adjusted_value * quantity,
      pl: (adjusted_value * quantity) - (cost_per_unit * quantity),
      roi_pct: roi_percent(cost_per_unit * quantity, (adjusted_value * quantity) - (cost_per_unit * quantity))
    )

    redirect_back fallback_location: portfolio_path, notice: "Holding updated."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: portfolio_path, alert: e.record.errors.full_messages.to_sentence
  rescue
    redirect_back fallback_location: portfolio_path, alert: "Could not update holding."
  end

  def destroy
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    holding = Holding.where(user_id: current_user.id).find(params[:id])
    holding.destroy

    redirect_back fallback_location: portfolio_path, notice: "Holding removed."
  rescue
    redirect_back fallback_location: portfolio_path, alert: "Could not remove holding."
  end

  private

  def holding_params
    params.require(:holding).permit(
      :product_id,
      :set_slug,
      :type_code,
      :image_url,
      :era,
      :set_name,
      :product_type,
      :value,
      :quantity,
      :cost_per_unit,
      :purchase_date,
      :condition
    )
  end

  def current_user
    return @current_user if defined?(@current_user)
    @current_user = User.find_by(id: session[:user_id])
  end

  def decimal_value(value)
    BigDecimal(value.to_s)
  rescue
    BigDecimal("0")
  end

  def roi_percent(total_cost, pl)
    total_cost = decimal_value(total_cost)
    pl = decimal_value(pl)

    return BigDecimal("0") if total_cost <= 0

    ((pl / total_cost) * 100).round(2)
  rescue
    BigDecimal("0")
  end

  def find_or_create_product_for_holding(attrs, base_value)
    return Product.find_by(id: attrs[:product_id]) if attrs[:product_id].present? && defined?(Product)

    return nil unless defined?(Product)

    set_slug = attrs[:set_slug].to_s.strip
    type_code = attrs[:type_code].to_s.strip
    sku = [ set_slug, type_code ].reject(&:blank?).join(":")

    product = Product.find_by(sku: sku) if sku.present?
    return product if product

    product_attrs = {}

    product_attrs[:sku] = sku if Product.column_names.include?("sku") && sku.present?
    product_attrs[:era] = attrs[:era].to_s if Product.column_names.include?("era")
    product_attrs[:set_name] = attrs[:set_name].to_s if Product.column_names.include?("set_name")
    product_attrs[:product_type] = attrs[:product_type].to_s if Product.column_names.include?("product_type")
    product_attrs[:name] = attrs[:product_type].to_s if Product.column_names.include?("name")
    product_attrs[:image] = attrs[:image_url].to_s if Product.column_names.include?("image")
    product_attrs[:value] = base_value if Product.column_names.include?("value")

    Product.create!(product_attrs)
  rescue
    nil
  end

  def create_summary_entry_safe(holding, action)
    return unless defined?(SummaryEntry)

    cols = SummaryEntry.column_names
    attrs = {}

    attrs[:user_id] = current_user.id if cols.include?("user_id")
    attrs[:action] = action if cols.include?("action")
    attrs[:era] = holding.era.to_s if cols.include?("era")
    attrs[:set_name] = holding.set_name.to_s if cols.include?("set_name")
    attrs[:product_type] = holding.product_type.to_s if cols.include?("product_type")
    attrs[:condition] = holding.condition.to_s if cols.include?("condition")
    attrs[:quantity] = holding.quantity.to_i if cols.include?("quantity")
    attrs[:cost_per_unit] = holding.cost_per_unit if cols.include?("cost_per_unit")
    attrs[:purchase_date] = holding.purchase_date if cols.include?("purchase_date")
    attrs[:value] = holding.value if cols.include?("value")
    attrs[:image_url] = holding.image.to_s if cols.include?("image_url")

    SummaryEntry.create!(attrs)
  rescue
    nil
  end
end
