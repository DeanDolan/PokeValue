require "test_helper"
require "securerandom"

class UserTest < ActiveSupport::TestCase
  def build_user(attributes = {})
    User.new({
      username: "testuser_#{SecureRandom.hex(4)}",
      country_code: "IE",
      revolut_tag: "testtag#{SecureRandom.hex(3)}",
      password: "Password123!",
      password_confirmation: "Password123!"
    }.merge(attributes))
  end

  test "valid user can be created" do
    user = build_user

    assert user.valid?, user.errors.full_messages.join(", ")
  end

  test "user password is authenticated securely" do
    user = build_user

    assert user.save, user.errors.full_messages.join(", ")
    assert user.authenticate("Password123!")
    assert_not user.authenticate("WrongPassword123!")
  end

  test "username must be unique" do
    username = "duplicateuser#{SecureRandom.hex(4)}"

    first_user = build_user(username: username)
    assert first_user.save, first_user.errors.full_messages.join(", ")

    second_user = build_user(username: username)

    assert_not second_user.valid?
  end
end
