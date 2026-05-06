class RegistrationsController < ApplicationController
  # Shows the registration form
  def new
    @user = User.new
  end

  # Creates a new account and logs the user in when registration succeeds
  def create
    username = params[:username].to_s.strip
    revolut_tag = params[:revolut_tag].to_s.strip
    password = params[:password].to_s
    password_confirmation = params[:password_confirmation].to_s

    if username.blank?
      flash.now[:alert] = "Username is required."
      render :new, status: :unprocessable_entity
      return
    end

    if username.length < User::USERNAME_MIN || username.length > User::USERNAME_MAX
      flash.now[:alert] = "Username must be 5-15 characters long."
      render :new, status: :unprocessable_entity
      return
    end

    unless username.match?(/\A[A-Za-z0-9._-]+\z/)
      flash.now[:alert] = "Username can only contain letters, numbers, dots, underscores or dashes."
      render :new, status: :unprocessable_entity
      return
    end

    if username.include?("@")
      flash.now[:alert] = "Username must not be an email address."
      render :new, status: :unprocessable_entity
      return
    end

    if params[:country_code].blank?
      flash.now[:alert] = "Country is required."
      render :new, status: :unprocessable_entity
      return
    end

    if revolut_tag.blank?
      flash.now[:alert] = "Revolut Tag is required."
      render :new, status: :unprocessable_entity
      return
    end

    unless revolut_tag.match?(/\A@?[A-Za-z0-9._-]{3,30}\z/)
      flash.now[:alert] = "Revolut Tag must contain 3-30 letters, numbers, dots, underscores or dashes. Example: @dola123."
      render :new, status: :unprocessable_entity
      return
    end

    if password.blank?
      flash.now[:alert] = "Password is required."
      render :new, status: :unprocessable_entity
      return
    end

    if password_confirmation.blank?
      flash.now[:alert] = "Password confirmation is required."
      render :new, status: :unprocessable_entity
      return
    end

    if password != password_confirmation
      flash.now[:alert] = "Passwords do not match."
      render :new, status: :unprocessable_entity
      return
    end

    if password.length < User::PASSWORD_MIN || password.length > User::PASSWORD_MAX
      flash.now[:alert] = "Password must be 12-20 characters long."
      render :new, status: :unprocessable_entity
      return
    end

    unless password.match?(/[A-Z]/)
      flash.now[:alert] = "Password must include at least one uppercase letter."
      render :new, status: :unprocessable_entity
      return
    end

    unless password.match?(/[a-z]/)
      flash.now[:alert] = "Password must include at least one lowercase letter."
      render :new, status: :unprocessable_entity
      return
    end

    unless password.match?(/\d/)
      flash.now[:alert] = "Password must include at least one number."
      render :new, status: :unprocessable_entity
      return
    end

    unless password.match?(/[^A-Za-z0-9]/)
      flash.now[:alert] = "Password must include at least one symbol."
      render :new, status: :unprocessable_entity
      return
    end

    if password.downcase.include?(username.downcase)
      flash.now[:alert] = "Password cannot contain your username."
      render :new, status: :unprocessable_entity
      return
    end

    unless registration_checkbox_accepted?(:account_safety_accepted)
      flash.now[:alert] = "You must confirm that you understand the account safety notice before registering."
      render :new, status: :unprocessable_entity
      return
    end

    unless registration_checkbox_accepted?(:revolut_tag_visibility_accepted)
      flash.now[:alert] = "You must confirm that you understand your Revolut tag may be shown during payment-related actions."
      render :new, status: :unprocessable_entity
      return
    end

    unless registration_checkbox_accepted?(:platform_terms_accepted)
      flash.now[:alert] = "You must agree to the account safety notice, payment visibility notice, security notice and platform terms before registering."
      render :new, status: :unprocessable_entity
      return
    end

    @user = User.new(
      username: username,
      country_code: params[:country_code],
      revolut_tag: revolut_tag,
      password: password,
      password_confirmation: password_confirmation
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

  private

  # Checks whether a required registration confirmation checkbox was accepted
  def registration_checkbox_accepted?(key)
    params[key].to_s == "1"
  end
end
