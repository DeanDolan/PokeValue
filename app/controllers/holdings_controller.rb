class HoldingsController < ApplicationController
  # Creates a portfolio holding from the Add to Portfolio form.
  def create
    return redirect_to(portfolio_login_required_path, alert: "Please log in to view your Portfolio.") unless current_user

    attrs = holding_params

    quantity = attrs[:quantity].to_i
    quantity = 1 if quantity <= 0

    cost_per_unit = money_value(attrs[:cost_per_unit])
    submitted_value = money_value(attrs[:value])
    condition = attrs[:condition].to_s.strip

    product = save_product_for_holding(attrs, submitted_value)

    base_value = product_value_for_holding(attrs, product, submitted_value)
    adjusted_value = Holding.adjusted_value_for_condition(base_value, condition)

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
      roi_pct: calculate_roi(cost_per_unit * quantity, (adjusted_value * quantity) - (cost_per_unit * quantity)),
      purchase_date: attrs[:purchase_date].presence || Date.current,
      image: attrs[:image_url].to_s
    )

    holding.save!
    create_summary_entry(holding, "ADDED")

    redirect_back fallback_location: portfolio_path, notice: "Added to portfolio."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: portfolio_path, alert: e.record.errors.full_messages.to_sentence
  rescue
    redirect_back fallback_location: portfolio_path, alert: "Could not add product to portfolio."
  end

  # Loads the portfolio edit page for one holding.
  def edit
    return redirect_to(portfolio_login_required_path, alert: "Please log in to view your Portfolio.") unless current_user

    @holding = holding_scope_for_current_user.find(params[:id])
    @condition_options = condition_options

    render "portfolios/edit"
  end

  # Updates holding quantity, cost, condition, value and calculated totals.
  def update
    return redirect_to(portfolio_login_required_path, alert: "Please log in to view your Portfolio.") unless current_user

    holding = holding_scope_for_current_user.find(params[:id])
    attrs = holding_params

    quantity = attrs[:quantity].presence || holding.quantity
    quantity = quantity.to_i
    quantity = 1 if quantity <= 0

    cost_per_unit =
      if attrs[:cost_per_unit].present?
        money_value(attrs[:cost_per_unit])
      else
        money_value(holding.cost_per_unit)
      end

    condition = attrs[:condition].presence || holding.condition.to_s

    submitted_value =
      if attrs[:value].present?
        money_value(attrs[:value])
      else
        BigDecimal("0")
      end

    base_value =
      if positive_number?(submitted_value)
        submitted_value
      else
        saved_product_value = product_value(holding.product)
        positive_number?(saved_product_value) ? saved_product_value : money_value(holding.value)
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
      roi_pct: calculate_roi(cost_per_unit * quantity, (adjusted_value * quantity) - (cost_per_unit * quantity))
    )

    redirect_to portfolio_path, notice: "Holding updated."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: portfolio_path, alert: e.record.errors.full_messages.to_sentence
  rescue
    redirect_back fallback_location: portfolio_path, alert: "Could not update holding."
  end

  # Loads the sold form for one holding.
  def sold
    return redirect_to(portfolio_login_required_path, alert: "Please log in to view your Portfolio.") unless current_user

    @holding = holding_scope_for_current_user.find(params[:id])

    render "portfolios/sold"
  end

  # Marks part or all of a holding as sold.
  def mark_sold
    return redirect_to(portfolio_login_required_path, alert: "Please log in to view your Portfolio.") unless current_user

    holding = holding_scope_for_current_user.find(params[:id])
    sell_holding(holding)

    redirect_to portfolio_path, notice: "Product marked as sold."
  rescue ActiveRecord::RecordNotFound
    redirect_to portfolio_path, alert: "Holding not found."
  rescue ActionController::BadRequest
    redirect_to sold_holding_path(params[:id]), alert: "Could not process sale details."
  rescue
    redirect_to portfolio_path, alert: "Could not mark product as sold."
  end

  # Removes a holding that belongs to the current user.
  def destroy
    return redirect_to(portfolio_login_required_path, alert: "Please log in to view your Portfolio.") unless current_user

    holding = holding_scope_for_current_user.find(params[:id])
    delete_holding(holding)

    redirect_back fallback_location: portfolio_path, notice: "Holding removed."
  rescue ActiveRecord::RecordNotFound
    redirect_back fallback_location: portfolio_path, alert: "Holding not found."
  rescue
    redirect_back fallback_location: portfolio_path, alert: "Could not remove product."
  end

  private

  # Allows only the holding form fields that should be saved.
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

  # Finds the logged-in user from the Rails session.
  def current_user
    return @current_user if defined?(@current_user)

    @current_user = User.find_by(id: session[:user_id])
  end

  # Finds holdings for the current user or all holdings for admin users.
  def holding_scope_for_current_user
    return Holding.all if holding_admin_user?

    Holding.where(user_id: current_user.id)
  end

  # Checks whether the current user is an admin.
  def holding_admin_user?
    user = current_user
    return false unless user

    return true if user.respond_to?(:admin?) && user.admin?
    return true if user.respond_to?(:admin) && !!user.admin

    false
  rescue
    false
  end

  # Returns condition options for the edit form.
  def condition_options
    [
      "Mint Sealed",
      "Loosely Sealed",
      "Mini Tear/Hole (<2cm)",
      "Unsealed",
      "Small Tear (>2cm)",
      "Big Tear (>1 inch)",
      "Small Imperfections",
      "Big Imperfections",
      "Pressure Marks",
      "Slightly Dented",
      "Heavy Dented",
      "Damaged",
      "Box Only",
      "Contents Only"
    ]
  end

  # Sells part or all of a holding and records a sold summary entry.
  def sell_holding(holding)
    sold_quantity = params[:sold_quantity].to_i
    sell_price = money_value(params[:sold_price])
    sale_date = sold_sale_date

    raise ActionController::BadRequest if sold_quantity <= 0
    raise ActionController::BadRequest if sold_quantity > holding.quantity.to_i
    raise ActionController::BadRequest if sell_price <= 0

    ActiveRecord::Base.transaction do
      create_sold_summary(holding, sold_quantity, sell_price, sale_date)

      remaining_quantity = holding.quantity.to_i - sold_quantity

      if remaining_quantity <= 0
        delete_holding(holding)
      else
        cost_per_unit = money_value(holding.cost_per_unit)
        current_value = money_value(holding.value)

        holding.update!(
          quantity: remaining_quantity,
          total_cost: cost_per_unit * remaining_quantity,
          total_value: current_value * remaining_quantity,
          pl: (current_value * remaining_quantity) - (cost_per_unit * remaining_quantity),
          roi_pct: calculate_roi(cost_per_unit * remaining_quantity, (current_value * remaining_quantity) - (cost_per_unit * remaining_quantity))
        )
      end
    end
  end

  # Reads the submitted sale date or uses today's date.
  def sold_sale_date
    Date.parse(params[:sale_date].to_s)
  rescue
    Date.current
  end

  # Creates a sold row in the portfolio summary.
  def create_sold_summary(holding, quantity, sell_price, sale_date)
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

  # Deletes a holding safely.
  def delete_holding(holding)
    ActiveRecord::Base.transaction do
      remove_marketplace_links(holding)
      remove_summary_links(holding)

      begin
        holding.destroy!
      rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::DeleteRestrictionError, ActiveRecord::InvalidForeignKey
        Holding.where(id: holding.id).delete_all
      end
    end
  end

  # Removes holding references from marketplace rows before deleting the holding.
  def remove_marketplace_links(holding)
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

  # Removes holding references from summary rows before deleting the holding.
  def remove_summary_links(holding)
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

  # Checks whether a database column can be nil.
  def nullable_column?(klass, column_name)
    column = klass.columns_hash[column_name.to_s]
    return true unless column

    column.null
  rescue
    true
  end

  # Converts form values into BigDecimal so money calculations are safer.
  def money_value(value)
    BigDecimal(value.to_s)
  rescue
    BigDecimal("0")
  end

  # Checks whether a decimal value is above zero.
  def positive_number?(value)
    money_value(value) > 0
  rescue
    false
  end

  # Calculates ROI percentage from total cost and profit/loss.
  def calculate_roi(total_cost, pl)
    total_cost = money_value(total_cost)
    pl = money_value(pl)

    return BigDecimal("0") if total_cost <= 0

    ((pl / total_cost) * 100).round(2)
  rescue
    BigDecimal("0")
  end

  # Finds an existing product or creates a basic one for the holding.
  def save_product_for_holding(attrs, base_value)
    return nil unless defined?(Product)

    product_from_id = Product.find_by(id: attrs[:product_id]) if attrs[:product_id].present?
    return product_from_id if product_from_id && positive_number?(product_value(product_from_id))

    product = matching_product_for_holding(attrs)
    return product if product

    set_slug = attrs[:set_slug].to_s.strip
    type_code = attrs[:type_code].to_s.strip
    sku = [ set_slug, type_code ].reject(&:blank?).join(":")

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

  # Gets the product value that should be used for the holding.
  def product_value_for_holding(attrs, product, submitted_value)
    saved_product_value = product_value(product)
    return saved_product_value if positive_number?(saved_product_value)

    existing_product = matching_product_for_holding(attrs)
    existing_value = product_value(existing_product)
    return existing_value if positive_number?(existing_value)

    return submitted_value if positive_number?(submitted_value)

    BigDecimal("0")
  rescue
    BigDecimal("0")
  end

  # Finds the matching product row using SKU and product metadata.
  def matching_product_for_holding(attrs)
    return nil unless defined?(Product)

    products = []

    possible_skus_for(attrs).each do |sku|
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

    products.compact.uniq.max_by { |product| product_value(product).to_f }
  rescue
    nil
  end

  # Builds possible SKU formats so portfolio values still match product-page/admin values.
  def possible_skus_for(attrs)
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
  def product_value(product)
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

      value = money_value(product[column])
      return value if value > 0
    end

    cents_value_columns.each do |column|
      next unless product.has_attribute?(column)

      value = money_value(product[column]) / 100
      return value if value > 0
    end

    BigDecimal("0")
  rescue
    BigDecimal("0")
  end

  # Stores a summary row so the portfolio can show added items in the history modal.
  def create_summary_entry(holding, action)
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
