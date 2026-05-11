module Admin
  class ProductValuesController < BaseController
    # This action updates one product value from the admin edit form.
    # It is used when the admin changes a sealed product's price/value.
    def update
      # Get the SKU from the URL params and clean any spaces from the start/end.
      # The SKU is used to find the correct product.
      sku = params[:sku].to_s.strip

      # This checks that the SKU only contains safe characters.
      # It allows letters, numbers, dashes, underscores and double-dash sections.
      # If the SKU has strange characters, the app treats it as not found.
      raise ActiveRecord::RecordNotFound unless sku.match?(/\A[a-zA-Z0-9\-_]+(?:--[a-zA-Z0-9\-_]+)*\z/)

      # This stops extremely long SKU values being accepted.
      # It protects the admin update route from bad or messy input.
      raise ActiveRecord::RecordNotFound if sku.length > 220

      # This variable is created outside the transaction so it can still be used after the product is found/created.
      product = nil

      # Everything inside this block happens as one database transaction.
      # That means if something fails halfway through, Rails rolls the database changes back.
      Product.transaction do
        # Lock the product row while updating it.
        # This prevents two admin updates from changing the same product at the exact same time.
        # If the product does not already exist, Rails creates a new unsaved Product object using this SKU.
        product = Product.lock.find_or_initialize_by(sku: sku)

        # Store the old value before changing it.
        # This is needed for the admin audit log so the app can record what changed.
        old_value = product.value

        # Update the product name from the form.
        # If the submitted name is blank, use "Product" as a fallback.
        product.name = params[:name].to_s.strip.presence || "Product"

        # Update the product value.
        # decimal_param safely converts the value and blocks negative or unrealistic values.
        product.value = decimal_param(params[:value], max: 1_000_000)

        # Update the set name if this Product model has a set_name column.
        # respond_to? is used so this code will not break if the column/method does not exist.
        product.set_name = params[:set_name].to_s.strip if product.respond_to?(:set_name=)

        # Update the era if the Product model supports it.
        product.era = params[:era].to_s.strip if product.respond_to?(:era=)

        # Update the product type if the Product model supports it.
        # The form sends this as product_type_name.
        product.product_type = params[:product_type_name].to_s.strip if product.respond_to?(:product_type=)

        # Update the product image path/url if the Product model supports it.
        product.image = params[:image_url].to_s.strip if product.respond_to?(:image=)

        # Save all product changes to the database.
        # save! is used so Rails raises an error if saving fails.
        product.save!

        # If the Product model has this method, refresh all holdings that use this product.
        # This keeps user portfolio values in sync after an admin changes a product value.
        Product.refresh_holdings_for_product!(product) if Product.respond_to?(:refresh_holdings_for_product!)

        # Record the admin change in the audit log.
        # This keeps a history of who changed the value, what the old value was,
        # what the new value is, and request details such as IP/user agent if handled by AdminAudit.
        AdminAudit.record_change!(
          user: current_user,
          product: product,
          old_value: old_value,
          new_value: product.value,
          request: request
        )
      end

      # After the update finishes, send the admin back to the page they came from.
      # safe_return_to makes sure the redirect stays inside the app.
      # If return_to is missing or unsafe, it falls back to the portfolio page.
      redirect_to safe_return_to(params[:return_to], fallback: portfolio_path), notice: "Value updated.", status: :see_other
    end
  end
end
