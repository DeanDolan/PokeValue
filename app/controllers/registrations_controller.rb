class RegistrationsController < ApplicationController
  # Shows the registration form
  def new
    @user = User.new
  end

  # Creates a new account and logs the user in when registration succeeds
  def create
    username = params[:username].to_s.strip
    revolut_tag = params[:revolut_tag].to_s.strip

    if username.length < 5 || username.length > 15
      redirect_to register_path,
                  alert: "Username must be between 5 and 15 characters long. You entered #{username.length} characters.",
                  status: :see_other
      return
    end

    if revolut_tag.blank?
      redirect_to register_path,
                  alert: "Revolut Tag is required.",
                  status: :see_other
      return
    end

    @user = User.new(
      username: username,
      country_code: params[:country_code],
      revolut_tag: revolut_tag,
      password: params[:password],
      password_confirmation: params[:password_confirmation]
    )

    if @user.save
      session[:user_id] = @user.id

      redirect_to portfolio_path,
                  notice: "Welcome, #{@user.username}! Your account has been created.",
                  status: :see_other
    else
      flash.now[:alert] = @user.errors.full_messages.first || "Could not create account."
      render :new, status: :unprocessable_entity
    end
  end
end
