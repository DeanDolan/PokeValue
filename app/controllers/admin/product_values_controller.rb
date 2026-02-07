# app/controllers/admin/product_values_controller.rb
module Admin
  class ProductValuesController < ApplicationController
    include Authentication

    before_action :require_admin

    def update
      sku = params[:sku].to_s
      raise ActiveRecord::RecordNotFound unless sku.match?(/\A[a-zA-Z0-9\-_]+(?:--[a-zA-Z0-9\-_]+)*\z/)
      raise ActiveRecord::RecordNotFound if sku.length > 220

      raw = params[:value].to_s
      value = begin
        BigDecimal(raw)
      rescue
        nil
      end
      raise ActionController::BadRequest if value.nil?
      raise ActionController::BadRequest if value < 0
      raise ActionController::BadRequest if value > 1_000_000

      name = params[:name].to_s.strip
      name = "Product" if name.blank?

      return_to = safe_return_to(params[:return_to])

      Product.transaction do
        product = Product.lock.find_or_initialize_by(sku: sku)
        product.name = name if product.name.blank?
        old = product.value
        product.value = value
        product.save!

        AdminAudit.create!(
          user_id: current_user.id,
          sku: sku,
          old_value: old,
          new_value: value,
          ip: request.remote_ip,
          user_agent: request.user_agent.to_s
        )
      end

      redirect_to(return_to || portfolio_path, notice: "Value updated.", status: :see_other)
    end

    private

    def require_admin
      ok =
        if respond_to?(:admin_signed_in?)
          admin_signed_in?
        elsif respond_to?(:current_user) && current_user
          current_user.respond_to?(:admin?) ? current_user.admin? : false
        else
          false
        end
      redirect_to(root_path, alert: "Not authorized.", status: :see_other) unless ok
    end

    def safe_return_to(path)
      p = path.to_s
      return nil if p.blank?
      return nil unless p.start_with?("/")
      return nil if p.start_with?("//")
      p
    end
  end
end
