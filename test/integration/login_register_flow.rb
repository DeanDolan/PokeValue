require "test_helper"

class LoginRegisterFlowTest < ActionDispatch::IntegrationTest
  test "user can register and is logged in" do
    get register_path
    assert_response :success

    assert_difference "User.count", 1 do
      post register_path, params: {
        username: "flowuser",
        country_code: "IE",
        revolut_tag: "@flowuser",
        password: "StrongPass1!",
        password_confirmation: "StrongPass1!",
        account_safety_accepted: "1",
        revolut_tag_visibility_accepted: "1",
        platform_terms_accepted: "1"
      }
    end

    assert_response :see_other
    assert_redirected_to portfolio_path
    assert_equal User.last.id, session[:user_id]
  end

  test "user can login and logout" do
    user = users(:standard_user)

    post login_path, params: {
      username: user.username,
      password: "StrongPass1!"
    }

    assert_response :see_other
    assert_redirected_to portfolio_path
    assert_equal user.id, session[:user_id]

    delete logout_path

    assert_response :see_other
    assert_redirected_to portfolio_path
    assert_nil session[:user_id]
  end
end
