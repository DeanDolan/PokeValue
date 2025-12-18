# References:
# - Rails controllers / strong params:
#   https://guides.rubyonrails.org/action_controller_overview.html
# - Active Record basics (find_or_initialize_by, callbacks, validations):
#   https://guides.rubyonrails.org/active_record_basics.html

class HoldingsController < ApplicationController
  # Shared auth helpers (current_user, user_signed_in? etc.)
  include Authentication

  # Nobody should hit these actions without being logged in
  before_action :require_login!

  def create
    # Strong params I expect from the add-holding form
    permitted = holding_params

    # Extra identifiers used to build/find the Product
    set_slug  = params.dig(:holding, :set_slug).to_s
    type_code = params.dig(:holding, :type_code).to_s
    sku       = [ set_slug, type_code ].join(":")

    # Create or find the Product for this holding based on SKU
    product = Product.find_or_initialize_by(sku: sku)
    product.name ||= "#{permitted[:set_name]} – #{permitted[:product_type]}"
    product.save!

    # If user already has a holding for this product, update the existing one
    existing = current_user.holdings.find_by(product_id: product.id)
    if existing
      # Increase quantity and overwrite the latest cost/value info
      new_qty = existing.quantity.to_i + permitted[:quantity].to_i

      existing.quantity      = new_qty
      existing.cost_per_unit = permitted[:cost_per_unit]
      existing.purchase_date = permitted[:purchase_date]
      existing.condition     = permitted[:condition]
      existing.value         = permitted[:value]
      existing.total_cost    = new_qty * existing.cost_per_unit.to_d
      existing.total_value   = new_qty * existing.value.to_d
      existing.save!

      redirect_to portfolio_path, notice: "Product updated in portfolio successfully!"
    else
      # New holding for this user + product
      holding = current_user.holdings.build(permitted)
      holding.product_id  = product.id
      holding.total_cost  = holding.quantity.to_i * holding.cost_per_unit.to_d
      holding.total_value = holding.quantity.to_i * holding.value.to_d
      holding.save!

      redirect_to portfolio_path, notice: "Product added to portfolio successfully!"
    end
  rescue ActiveRecord::RecordInvalid => e
    # On validation problems, I surface the first error as a flash
    redirect_to portfolio_path, alert: e.record.errors.full_messages.first || "Could not add product."
  end

  def edit
    # Only allow editing holdings that belong to the current user
    @holding = current_user.holdings.find(params[:id])
  end

  def update
    @holding = current_user.holdings.find(params[:id])

    if @holding.update(holding_params)
      # Recalculate totals whenever editable fields change
      @holding.total_cost  = @holding.quantity.to_i * @holding.cost_per_unit.to_d
      @holding.total_value = @holding.quantity.to_i * @holding.value.to_d
      @holding.save!
      redirect_to portfolio_path, notice: "Holding updated."
    else
      flash.now[:alert] = @holding.errors.full_messages.first || "Update failed."
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    # Soft guard by scoping to current_user
    h = current_user.holdings.find(params[:id])
    h.destroy
    redirect_to portfolio_path, notice: "Holding removed."
  end

  private

  # Simple guard to push people back to portfolio if they are not logged in
  def require_login!
    redirect_to portfolio_path, alert: "Please log in to manage holdings." unless user_signed_in?
  end

  # Strong params for holdings
  def holding_params
    hp = params.require(:holding).permit(
      :era,
      :set_name,
      :product_type,
      :quantity,
      :cost_per_unit,
      :purchase_date,
      :condition,
      :value
    )

    # Normalise to numeric types so calculations stay consistent
    hp[:quantity]      = (hp[:quantity].presence      || 1).to_i
    hp[:cost_per_unit] = (hp[:cost_per_unit].presence || 0).to_d
    # If value is blank I treat it as 0 rather than mirroring cost_per_unit
    hp[:value]         = (hp[:value].presence         || 0).to_d

    hp
  end
end
