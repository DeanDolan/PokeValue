class HoldingsController < ApplicationController
  include Authentication

  def create
    unless current_user
      redirect_to login_path
      return
    end

    set_slug  = params.dig(:holding, :set_slug).to_s
    type_code = params.dig(:holding, :type_code).to_s

    product = find_product(set_slug, type_code)

    unless product
      redirect_back fallback_location: sets_path, alert: "Product not found for #{set_slug}:#{type_code}"
      return
    end

    holding = current_user.holdings.new(create_params)
    holding.product = product

    if holding.respond_to?(:value)
      if holding.value.present?
        holding.value = holding.value.to_d
      elsif product.respond_to?(:value) && product.value.present?
        holding.value = product.value.to_d
      end
    end

    if holding.save
      redirect_back fallback_location: portfolio_path, notice: "Added to portfolio."
    else
      redirect_back fallback_location: portfolio_path, alert: holding.errors.full_messages.to_sentence
    end
  end

  def edit
    @holding = current_user.holdings.find(params[:id])
  end

  def update
    holding = current_user.holdings.find(params[:id])

    if holding.update(update_params)
      redirect_back fallback_location: portfolio_path, notice: "Updated."
    else
      redirect_back fallback_location: portfolio_path, alert: holding.errors.full_messages.to_sentence
    end
  end

  def destroy
    holding = current_user.holdings.find(params[:id])
    holding.destroy
    redirect_back fallback_location: portfolio_path, notice: "Removed."
  end

  private

  def create_params
    params.require(:holding).permit(
      :era,
      :set_name,
      :product_type,
      :quantity,
      :cost_per_unit,
      :purchase_date,
      :condition,
      :value
    )
  end

  def update_params
    params.require(:holding).permit(
      :quantity,
      :cost_per_unit,
      :purchase_date,
      :condition
    )
  end

  def find_product(set_slug, type_code)
    return nil if set_slug.blank? || type_code.blank?

    sku = "#{set_slug}:#{type_code}"
    cols = Product.column_names

    if cols.include?("sku")
      p = Product.find_by(sku: sku)
      return p if p
    end

    if cols.include?("set_slug") && cols.include?("type_code")
      p = Product.find_by(set_slug: set_slug, type_code: type_code)
      return p if p
    end

    if cols.include?("set_slug") && cols.include?("product_type")
      p = Product.find_by(set_slug: set_slug, product_type: type_code)
      return p if p
    end

    if cols.include?("slug") && cols.include?("type_code")
      p = Product.find_by(slug: set_slug, type_code: type_code)
      return p if p
    end

    if cols.include?("slug") && cols.include?("product_type")
      p = Product.find_by(slug: set_slug, product_type: type_code)
      return p if p
    end

    nil
  end
end
