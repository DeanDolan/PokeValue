require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "user is valid with valid details" do
    user = valid_user("validuser1")

    assert user.valid?
  end

  test "username is required" do
    user = valid_user("validuser2")
    user.username = nil

    assert_not user.valid?
    assert_includes user.errors[:username], "cant be blank"
  end

  test "country code is required" do
    user = valid_user("validuser3")
    user.country_code = nil

    assert_not user.valid?
    assert_includes user.errors[:country_code], "cant be blank"
  end

  test "revolut tag is required on create" do
    user = valid_user("validuser4")
    user.revolut_tag = nil

    assert_not user.valid?
    assert_includes user.errors[:revolut_tag], "is required"
  end

  test "password must be complex" do
    user = valid_user("validuser5", "weakpassword")

    assert_not user.valid?
    assert user.errors[:password].any?
  end

  test "password cannot contain username" do
    user = valid_user("testing", "Testing123!")

    assert_not user.valid?
    assert_includes user.errors[:password], "cannot contain your username"
  end

  test "user authenticates with correct password" do
    user = valid_user("validuser6")
    user.save!

    assert user.authenticate("StrongPass1!")
  end

  test "user does not authenticate with wrong password" do
    user = valid_user("validuser7")
    user.save!

    assert_not user.authenticate("WrongPass1!")
  end

  private

  def valid_user(username, password = "StrongPass1!")
    User.new(
      username: username,
      country_code: "IE",
      revolut_tag: "@#{username}",
      password: password,
      password_confirmation: password
    )
  end
end
