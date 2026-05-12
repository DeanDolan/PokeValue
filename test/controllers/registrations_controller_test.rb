require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "new returns success" do
    get register_path

    assert_response :success
  end

  test "creates user with valid registration details" do
    assert_difference "User.count", 1 do
      post register_path, params: valid_registration_params
    end

    assert_response :see_other
    assert_redirected_to portfolio_path
    assert_equal User.last.id, session[:user_id]
    assert_equal "Welcome, newuser! Your account has been created.", flash[:notice]
  end

  test "does not create user with blank username" do
    assert_no_difference "User.count" do
      post register_path, params: valid_registration_params.merge(username: "")
    end

    assert_response :unprocessable_entity
    assert_equal "Username is required.", flash[:alert]
  end

  test "does not create user with weak password" do
    assert_no_difference "User.count" do
      post register_path, params: valid_registration_params.merge(
        password: "weakpassword",
        password_confirmation: "weakpassword"
      )
    end

    assert_response :unprocessable_entity
    assert_equal "Password must include at least one uppercase letter.", flash[:alert]
  end

  private

  def valid_registration_params
    {
      username: "newuser",
      country_code: "IE",
      revolut_tag: "@newuser",
      password: "StrongPass1!",
      password_confirmation: "StrongPass1!",
      account_safety_accepted: "1",
      revolut_tag_visibility_accepted: "1",
      platform_terms_accepted: "1"
    }
  end
end
