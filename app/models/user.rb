# References:
# - Active Record validations:
#   https://guides.rubyonrails.org/active_record_validations.html
# - has_secure_password:
#   https://api.rubyonrails.org/classes/ActiveModel/SecurePassword/ClassMethods.html
# - BCrypt for hashing:
#   https://github.com/codahale/bcrypt-ruby

class User < ApplicationRecord
  # Handles password + password_confirmation, hashing, and authenticate
  has_secure_password

  # Tie holdings to the user so they are cleaned up on delete
  has_many :holdings, dependent: :destroy

  USERNAME_MIN = 4
  PASSWORD_MIN = 12
  LOCK_LIMIT   = 5
  LOCK_WINDOW  = 15.minutes

  # Basic username validation so I always have a unique, non-trivial name
  validates :username,
            presence: true,
            uniqueness: true,
            length: { minimum: USERNAME_MIN }

  # Country is required so I can use it later for regional logic
  validates :country_code, presence: true

  # Extra password rules on top of has_secure_password
  validate :password_complexity, if: :password
  validate :password_not_include_username, if: :password

  # Store recovery answer as a BCrypt digest similar to the password
  def recovery_answer=(plain)
    self.recovery_answer_digest = BCrypt::Password.create(plain) if plain.present?
  end

  # Check a plain recovery answer against the stored digest
  def recovery_answer_matches?(plain)
    return false if recovery_answer_digest.blank? || plain.blank?
    BCrypt::Password.new(recovery_answer_digest) == plain
  end

  # Treat the account as locked if locked_at is still inside the lock window
  def locked?
    locked_at.present? && locked_at > LOCK_WINDOW.ago
  end

  # Increment failed attempts and stamp locked_at once the limit is hit
  def register_failed_login!
    update!(
      failed_attempts: failed_attempts + 1,
      locked_at: ((failed_attempts + 1) >= LOCK_LIMIT ? Time.current : locked_at)
    )
  end

  # Clear lock state after successful login or manual reset
  def reset_failed_logins!
    update!(failed_attempts: 0, locked_at: nil)
  end

  private

  # Enforce stronger passwords: length + variety of characters
  def password_complexity
    return if password.blank?

    too_short = password.length < PASSWORD_MIN
    no_upper  = password !~ /[A-Z]/
    no_lower  = password !~ /[a-z]/
    no_digit  = password !~ /\d/
    no_symbol = password !~ /[^A-Za-z0-9]/

    errors.add(:password, "must be at least #{PASSWORD_MIN} chars") if too_short
    errors.add(:password, "must include upper, lower, digit, symbol") if no_upper || no_lower || no_digit || no_symbol
  end

  # Avoid passwords that simply embed the username
  def password_not_include_username
    return if password.blank? || username.blank?
    errors.add(:password, "cannot contain your username") if password.downcase.include?(username.downcase)
  end
end
