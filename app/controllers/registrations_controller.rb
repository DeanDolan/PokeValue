class RegistrationsController < ApplicationController
  def new
    # Creates a blank User object for the registration page.
    # This does not save anything to the database.
    @user = User.new
  end

  def create
    # params contains the values submitted from the registration form.
    # to_s makes sure each value is treated as text, even if the field is missing.
    # strip removes extra spaces from the start and end of username and Revolut tag.
    username = params[:username].to_s.strip
    revolut_tag = params[:revolut_tag].to_s.strip
    password = params[:password].to_s
    password_confirmation = params[:password_confirmation].to_s

    # Runs the manual registration checks before creating the User object.
    # If something is wrong, registration_error returns a message.
    # If everything is valid, it returns nil.
    message = registration_error(username, revolut_tag, password, password_confirmation)

    # If an error message exists, stop this action immediately.
    # The user is sent back and the message is shown as a flash alert.
    return redirect_invalid_registration(message) if message

    # Builds a new User object using the cleaned form values.
    # This object is only in memory at this point.
    # It is not saved to the database until @user.save runs.
    @user = User.new(
      username: username,
      country_code: params[:country_code],
      revolut_tag: revolut_tag,
      password: password,
      password_confirmation: password_confirmation
    )

    if @user.save
      # Clears any previous session data for security.
      reset_session

      # Stores the new user's id in the session.
      # This is what logs the user in after registration.
      session[:user_id] = @user.id

      # Sends the new user to the portfolio page with a success message.
      # see_other is used after form submission to avoid duplicate form resubmission.
      redirect_to portfolio_path,
                  notice: "Welcome, #{@user.username}! Your account has been created.",
                  status: :see_other
    else
      # If the model save fails, use the first model validation error if available.
      # If no specific error is available, show a general fallback message.
      redirect_invalid_registration(@user.errors.full_messages.first || "Could not create account.")
    end
  end

  private

  def registration_error(username, revolut_tag, password, password_confirmation)
    # Returns the first validation error found.
    # Because each line uses return, the method stops as soon as one problem is found.
    return "Username is required." if username.blank?
    return "Username must be 5-15 characters long." if username.length < User::USERNAME_MIN || username.length > User::USERNAME_MAX
    return "Username can only contain letters, numbers, dots, underscores or dashes." unless username.match?(/\A[A-Za-z0-9._-]+\z/)
    return "Username must not be an email address." if username.include?("@")

    # Country is read directly from params because it is not cleaned into a local variable above.
    return "Country is required." if params[:country_code].blank?

    # The Revolut tag can be entered with or without @.
    # The User model later normalises it into @tag format before encrypting it.
    return "Revolut Tag is required." if revolut_tag.blank?
    return "Revolut Tag must contain 3-30 letters, numbers, dots, underscores or dashes. Example: @dola123." unless revolut_tag.match?(/\A@?[A-Za-z0-9._-]{3,30}\z/)

    # Checks the password fields before the User model tries to save.
    return "Password is required." if password.blank?
    return "Password confirmation is required." if password_confirmation.blank?
    return "Passwords do not match." if password != password_confirmation
    return "Password must be 12-20 characters long." if password.length < User::PASSWORD_MIN || password.length > User::PASSWORD_MAX
    return "Password must include at least one uppercase letter." unless password.match?(/[A-Z]/)
    return "Password must include at least one lowercase letter." unless password.match?(/[a-z]/)
    return "Password must include at least one number." unless password.match?(/\d/)
    return "Password must include at least one symbol." unless password.match?(/[^A-Za-z0-9]/)

    # Prevents weak passwords that contain the username.
    # downcase makes the check case-insensitive.
    return "Password cannot contain your username." if password.downcase.include?(username.downcase)

    # nil means no manual registration errors were found.
    nil
  end

  def redirect_invalid_registration(message)
    # Sends the user back to the page/modal they came from.
    # If Rails cannot work out the previous page, it falls back to the home page.
    # alert stores the message in the flash so it can be shown on the next page load.
    redirect_back fallback_location: root_path, alert: message, status: :see_other
  end
end
