require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "new redirects to portfolio" do
    get login_path

    assert_response :see_other
    assert_redirected_to portfolio_path
  end

  test "creates session with valid login" do
    user = users(:standard_user)

    post login_path, params: {
      username: user.username,
      password: "StrongPass1!"
    }

    assert_response :see_other
    assert_redirected_to portfolio_path
    assert_equal user.id, session[:user_id]
    assert_equal "Logged in successfully!", flash[:notice]
  end

  test "does not create session with wrong password" do
    post login_path, params: {
      username: users(:standard_user).username,
      password: "WrongPass1!"
    }

    assert_response :see_other
    assert_redirected_to portfolio_path
    assert_nil session[:user_id]
    assert_equal "Invalid username or password.", flash[:alert]
  end

  test "does not create session when username is blank" do
    post login_path, params: {
      username: "",
      password: "StrongPass1!"
    }

    assert_response :see_other
    assert_redirected_to portfolio_path
    assert_nil session[:user_id]
    assert_equal "Username field cannot be empty.", flash[:alert]
  end

  test "destroy clears session" do
    post login_path, params: {
      username: users(:standard_user).username,
      password: "StrongPass1!"
    }

    delete logout_path

    assert_response :see_other
    assert_redirected_to portfolio_path
    assert_nil session[:user_id]
    assert_equal "Logged out.", flash[:notice]
  end
end
