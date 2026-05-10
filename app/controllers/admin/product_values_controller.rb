module Admin
  class ProductValuesController < BaseController
    # Updates one product value from an admin edit form.
    def update
      sku = params[:sku].to_s.strip
      raise ActiveRecord::RecordNotFound unless sku.match?(/\A[a-zA-Z0-9\-_]+(?:--[a-zA-Z0-9\-_]+)*\z/)
      raise ActiveRecord::RecordNotFound if sku.length > 220

      product = nil

      Product.transaction do
        product = Product.lock.find_or_initialize_by(sku: sku)
        old_value = product.value

        product.name = params[:name].to_s.strip.presence || "Product"
        product.value = decimal_param(params[:value], max: 1_000_000)
        product.set_name = params[:set_name].to_s.strip if product.respond_to?(:set_name=)
        product.era = params[:era].to_s.strip if product.respond_to?(:era=)
        product.product_type = params[:product_type_name].to_s.strip if product.respond_to?(:product_type=)
        product.image = params[:image_url].to_s.strip if product.respond_to?(:image=)
        product.save!

        Product.refresh_holdings_for_product!(product) if Product.respond_to?(:refresh_holdings_for_product!)

        AdminAudit.record_change!(
          user: current_user,
          product: product,
          old_value: old_value,
          new_value: product.value,
          request: request
        )
      end

      redirect_to safe_return_to(params[:return_to], fallback: portfolio_path), notice: "Value updated.", status: :see_other
    end
  end
end
