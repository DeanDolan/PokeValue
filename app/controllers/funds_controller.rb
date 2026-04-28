class FundsController < ApplicationController
  helper_method :current_user

  def new
    redirect_to(root_path, alert: "Please log in.") unless current_user
  end

  def create
    return redirect_to(root_path, alert: "Please log in.") unless current_user

    amount_str = params[:amount].to_s.strip
    amount = BigDecimal(amount_str)
    cents = (amount * 100).to_i

    return redirect_to(new_fund_path, alert: "Amount must be greater than 0.") if cents <= 0
    return redirect_to(new_fund_path, alert: "Funds not supported for this account.") unless current_user.respond_to?(:balance_cents)

    ActiveRecord::Base.transaction do
      u = User.lock.find(current_user.id)
      u.update!(balance_cents: u.balance_cents.to_i + cents)
    end

    redirect_to(account_path, notice: "Funds added.")
  rescue
    redirect_to(new_fund_path, alert: "Could not add funds.")
  end

  private

  def current_user
    return @current_user if defined?(@current_user)
    @current_user = User.find_by(id: session[:user_id])
  end
end
