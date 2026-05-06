class HoldingsController < ApplicationController
  # Creates a portfolio holding from the Add to Portfolio form
  def create
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    attrs = holding_params

    # Defaults invalid or empty quantities to 1 so the holding can still be calculated safely.
    quantity = attrs[:quantity].to_i
    quantity = 1 if quantity <= 0

    # Converts submitted money fields into decimal values before doing portfolio calculations.
    cost_per_unit = decimal_value(attrs[:cost_per_unit])
    submitted_value = decimal_value(attrs[:value])
    condition = attrs[:condition].to_s.strip

    # Links the holding to an existing Product row, or creates a basic Product row if needed.
    product = find_or_create_product_for_holding(attrs, submitted_value)

    # Uses the best available product value instead of blindly trusting the hidden form value.
    base_value = best_base_value_for_holding(attrs, product, submitted_value)
    adjusted_value = Holding.adjusted_value_for_condition(base_value, condition)

    # Saves the holding with calculated cost, value, profit/loss, and ROI fields.
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

    # Adds a history entry for the portfolio summary modal.
    create_summary_entry_safe(holding, "ADDED")

    redirect_back fallback_location: portfolio_path, notice: "Added to portfolio."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: portfolio_path, alert: e.record.errors.full_messages.to_sentence
  rescue
    redirect_back fallback_location: portfolio_path, alert: "Could not add product to portfolio."
  end

  # Loads the edit page for one of the current user's holdings
  def edit
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    @holding = holding_scope_for_current_user.find(params[:id])
  end

  # Updates holding quantity, cost, condition, value and calculated totals
  def update
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    holding = holding_scope_for_current_user.find(params[:id])
    attrs = holding_params

    # Keeps the existing quantity unless a new valid quantity is submitted.
    quantity = attrs[:quantity].presence || holding.quantity
    quantity = quantity.to_i
    quantity = 1 if quantity <= 0

    # Keeps the old cost unless the user submits a new cost.
    cost_per_unit =
      if attrs[:cost_per_unit].present?
        decimal_value(attrs[:cost_per_unit])
      else
        decimal_value(holding.cost_per_unit)
      end

    condition = attrs[:condition].presence || holding.condition.to_s

    # Uses the submitted value first, then the linked product value, then the current holding value.
    submitted_value =
      if attrs[:value].present?
        decimal_value(attrs[:value])
      else
        BigDecimal("0")
      end

    base_value =
      if positive_decimal?(submitted_value)
        submitted_value
      else
        product_value = value_from_product(holding.product)
        positive_decimal?(product_value) ? product_value : decimal_value(holding.value)
      end

    adjusted_value = Holding.adjusted_value_for_condition(base_value, condition)

    # Recalculates totals so the portfolio table stays accurate after editing.
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

  # Removes a holding that belongs to the current user
  def destroy
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    if params[:remove_mode].to_s == "sold_summary_entry"
      delete_sold_summary_entry_safely(params[:id])
      return redirect_back fallback_location: portfolio_path, notice: "Sold entry deleted."
    end

    holding = holding_scope_for_current_user.find(params[:id])

    if params[:remove_mode].to_s == "sold"
      sell_holding_safely(holding)
      redirect_back fallback_location: portfolio_path, notice: "Product marked as sold."
    else
      delete_holding_safely(holding)
      redirect_back fallback_location: portfolio_path, notice: "Holding removed."
    end
  rescue ActiveRecord::RecordNotFound
    redirect_back fallback_location: portfolio_path, alert: "Holding not found."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: portfolio_path, alert: e.record.errors.full_messages.to_sentence
  rescue ActionController::BadRequest
    redirect_back fallback_location: portfolio_path, alert: "Could not process sale details."
  rescue
    redirect_back fallback_location: portfolio_path, alert: "Could not remove product."
  end

  private

  # Allows only the holding form fields that should be saved
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

  # Finds the logged-in user from the Rails session
  def current_user
    return @current_user if defined?(@current_user)
    @current_user = User.find_by(id: session[:user_id])
  end

  def holding_scope_for_current_user
    return Holding.all if holding_admin_user?

    Holding.where(user_id: current_user.id)
  end

  def holding_admin_user?
    user = current_user
    return false unless user

    return true if user.respond_to?(:admin?) && user.admin?
    return true if user.respond_to?(:admin) && !!user.admin

    false
  rescue
    false
  end

  def sell_holding_safely(holding)
    sold_quantity = params[:sold_quantity].to_i
    sell_price = decimal_value(params[:sold_price])
    sale_date = sold_sale_date

    raise ActionController::BadRequest if sold_quantity <= 0
    raise ActionController::BadRequest if sold_quantity > holding.quantity.to_i
    raise ActionController::BadRequest if sell_price <= 0

    ActiveRecord::Base.transaction do
      create_sold_summary_entry_safe(holding, sold_quantity, sell_price, sale_date)

      remaining_quantity = holding.quantity.to_i - sold_quantity

      if remaining_quantity <= 0
        delete_holding_safely(holding)
      else
        cost_per_unit = decimal_value(holding.cost_per_unit)
        current_value = decimal_value(holding.value)

        holding.update!(
          quantity: remaining_quantity,
          total_cost: cost_per_unit * remaining_quantity,
          total_value: current_value * remaining_quantity,
          pl: (current_value * remaining_quantity) - (cost_per_unit * remaining_quantity),
          roi_pct: roi_percent(cost_per_unit * remaining_quantity, (current_value * remaining_quantity) - (cost_per_unit * remaining_quantity))
        )
      end
    end
  end

  def sold_sale_date
    Date.parse(params[:sale_date].to_s)
  rescue
    Date.current
  end

  def create_sold_summary_entry_safe(holding, quantity, sell_price, sale_date)
    raise ActionController::BadRequest unless defined?(SummaryEntry)

    cols = SummaryEntry.column_names
    attrs = {}
    product_sku = holding.product&.sku.to_s

    set_slug =
      if product_sku.include?(":")
        product_sku.split(":", 2).first.to_s
      elsif product_sku.include?("--")
        product_sku.split("--", 2).first.to_s
      else
        ""
      end

    type_code =
      if product_sku.include?(":")
        product_sku.split(":", 2).last.to_s
      elsif product_sku.include?("--")
        product_sku.split("--", 2).last.to_s
      else
        ""
      end

    # Only writes fields that exist on the SummaryEntry model.
    attrs[:user_id] = current_user.id if cols.include?("user_id")
    attrs[:action] = "SOLD" if cols.include?("action")
    attrs[:era] = holding.era.to_s if cols.include?("era")
    attrs[:set_name] = holding.set_name.to_s if cols.include?("set_name")
    attrs[:set_slug] = set_slug if cols.include?("set_slug")
    attrs[:type_code] = type_code if cols.include?("type_code")
    attrs[:product_type] = holding.product_type.to_s if cols.include?("product_type")
    attrs[:condition] = holding.condition.to_s if cols.include?("condition")
    attrs[:quantity] = quantity.to_i if cols.include?("quantity")
    attrs[:cost_per_unit] = holding.cost_per_unit if cols.include?("cost_per_unit")
    attrs[:purchase_date] = sale_date if cols.include?("purchase_date")
    attrs[:value] = sell_price if cols.include?("value")
    attrs[:image_url] = holding.image.to_s if cols.include?("image_url")

    SummaryEntry.create!(attrs)
  end

  def delete_sold_summary_entry_safely(id)
    raise ActiveRecord::RecordNotFound unless defined?(SummaryEntry)

    scope = SummaryEntry.where(id: id)
    scope = scope.where(user_id: current_user.id) unless holding_admin_user?
    scope = scope.where(action: [ "SOLD", "Sold", "sold" ])

    entry = scope.first
    raise ActiveRecord::RecordNotFound unless entry

    begin
      entry.destroy!
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::DeleteRestrictionError, ActiveRecord::InvalidForeignKey
      scope.delete_all
    end
  end

  def delete_holding_safely(holding)
    ActiveRecord::Base.transaction do
      detach_holding_from_marketplace_rows(holding)
      detach_holding_from_summary_rows(holding)

      begin
        holding.destroy!
      rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::DeleteRestrictionError, ActiveRecord::InvalidForeignKey
        Holding.where(id: holding.id).delete_all
      end
    end
  end

  def detach_holding_from_marketplace_rows(holding)
    if defined?(MarketplaceListing) && MarketplaceListing.column_names.include?("holding_id")
      scope = MarketplaceListing.where(holding_id: holding.id)

      if nullable_column?(MarketplaceListing, "holding_id")
        update_attrs = { holding_id: nil }
        update_attrs[:updated_at] = Time.current if MarketplaceListing.column_names.include?("updated_at")
        scope.update_all(update_attrs)
      else
        scope.find_each do |listing|
          begin
            listing.destroy!
          rescue
            MarketplaceListing.where(id: listing.id).delete_all
          end
        end
      end
    end

    if defined?(MarketplacePurchase) && MarketplacePurchase.column_names.include?("holding_id")
      scope = MarketplacePurchase.where(holding_id: holding.id)

      if nullable_column?(MarketplacePurchase, "holding_id")
        update_attrs = { holding_id: nil }
        update_attrs[:updated_at] = Time.current if MarketplacePurchase.column_names.include?("updated_at")
        scope.update_all(update_attrs)
      else
        scope.delete_all
      end
    end
  end

  def detach_holding_from_summary_rows(holding)
    return unless defined?(SummaryEntry)
    return unless SummaryEntry.column_names.include?("holding_id")

    scope = SummaryEntry.where(holding_id: holding.id)

    if nullable_column?(SummaryEntry, "holding_id")
      update_attrs = { holding_id: nil }
      update_attrs[:updated_at] = Time.current if SummaryEntry.column_names.include?("updated_at")
      scope.update_all(update_attrs)
    else
      scope.delete_all
    end
  end

  def nullable_column?(klass, column_name)
    column = klass.columns_hash[column_name.to_s]
    return true unless column

    column.null
  rescue
    true
  end

  # Converts form values into BigDecimal so money calculations are safer
  def decimal_value(value)
    BigDecimal(value.to_s)
  rescue
    BigDecimal("0")
  end

  # Checks whether a decimal value is above zero.
  def positive_decimal?(value)
    decimal_value(value) > 0
  rescue
    false
  end

  # Calculates ROI percentage from total cost and profit/loss
  def roi_percent(total_cost, pl)
    total_cost = decimal_value(total_cost)
    pl = decimal_value(pl)

    return BigDecimal("0") if total_cost <= 0

    ((pl / total_cost) * 100).round(2)
  rescue
    BigDecimal("0")
  end

  # Finds an existing product or creates a basic one for the holding
  def find_or_create_product_for_holding(attrs, base_value)
    return nil unless defined?(Product)

    product_from_id = Product.find_by(id: attrs[:product_id]) if attrs[:product_id].present?
    return product_from_id if product_from_id && positive_decimal?(value_from_product(product_from_id))

    product = best_existing_product_for_holding(attrs)
    return product if product

    set_slug = attrs[:set_slug].to_s.strip
    type_code = attrs[:type_code].to_s.strip
    sku = [ set_slug, type_code ].reject(&:blank?).join(":")

    product_attrs = {}

    # Only writes columns that exist so this works safely with different Product table versions.
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

  # Uses the strongest available value source for the holding.
  def best_base_value_for_holding(attrs, product, submitted_value)
    product_value = value_from_product(product)
    return product_value if positive_decimal?(product_value)

    existing_product = best_existing_product_for_holding(attrs)
    existing_value = value_from_product(existing_product)
    return existing_value if positive_decimal?(existing_value)

    return submitted_value if positive_decimal?(submitted_value)

    BigDecimal("0")
  rescue
    BigDecimal("0")
  end

  # Finds the best existing product match using SKU and product metadata.
  def best_existing_product_for_holding(attrs)
    return nil unless defined?(Product)

    products = []

    sku_candidates_for(attrs).each do |sku|
      product = Product.find_by(sku: sku) if Product.column_names.include?("sku")
      products << product if product
    end

    if Product.column_names.include?("set_name") && Product.column_names.include?("product_type")
      product = Product.where(set_name: attrs[:set_name].to_s, product_type: attrs[:product_type].to_s).order(id: :desc).first
      products << product if product
    end

    if Product.column_names.include?("set_name") && Product.column_names.include?("name")
      product = Product.where(set_name: attrs[:set_name].to_s, name: attrs[:product_type].to_s).order(id: :desc).first
      products << product if product
    end

    products.compact.uniq.max_by { |product| value_from_product(product).to_f }
  rescue
    nil
  end

  # Builds possible SKU formats so portfolio values still match product-page/admin values.
  def sku_candidates_for(attrs)
    set_slug = attrs[:set_slug].to_s.strip
    type_code = attrs[:type_code].to_s.strip
    base_type = type_code.split("--").first.to_s

    return [] if set_slug.blank?

    [
      "#{set_slug}:#{type_code}",
      "#{set_slug}:#{base_type}",
      "#{set_slug}--#{type_code}",
      "#{set_slug}--#{base_type}"
    ].map(&:downcase).uniq
  end

  # Reads the product value safely from whichever value column exists.
  def value_from_product(product)
    return BigDecimal("0") unless product

    normal_value_columns = [
      "value",
      "product_value",
      "estimated_value",
      "value_eur",
      "product_value_eur",
      "estimated_value_eur",
      "price",
      "price_eur"
    ]

    cents_value_columns = [
      "value_cents",
      "product_value_cents",
      "estimated_value_cents",
      "price_cents"
    ]

    normal_value_columns.each do |column|
      next unless product.has_attribute?(column)

      value = decimal_value(product[column])
      return value if value > 0
    end

    cents_value_columns.each do |column|
      next unless product.has_attribute?(column)

      value = decimal_value(product[column]) / 100
      return value if value > 0
    end

    BigDecimal("0")
  rescue
    BigDecimal("0")
  end

  # Stores a summary row so the portfolio can show added items in the history modal
  def create_summary_entry_safe(holding, action)
    return unless defined?(SummaryEntry)

    cols = SummaryEntry.column_names
    attrs = {}

    # Only writes fields that exist on the SummaryEntry model.
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
