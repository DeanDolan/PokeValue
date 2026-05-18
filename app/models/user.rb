class User < ApplicationRecord
  # Adds password hashing and password authentication through password_digest
  has_secure_password

  # Connects the user to their portfolio, marketplace and community records
  has_many :holdings, dependent: :destroy
  has_many :watchlists, dependent: :destroy
  has_many :community_posts, dependent: :destroy
  has_many :community_comments, dependent: :destroy
  has_many :community_reactions, dependent: :destroy
  has_many :community_comment_reactions, dependent: :destroy
  has_many :hosted_raffles, class_name: "Raffle", foreign_key: :host_id, dependent: :destroy
  has_many :raffle_tickets, dependent: :nullify
  has_many :won_raffles, class_name: "Raffle", foreign_key: :winner_user_id, dependent: :nullify

  # Account security rules
  USERNAME_MIN = 5
  USERNAME_MAX = 15
  PASSWORD_MIN = 12
  PASSWORD_MAX = 20
  LOCK_LIMIT = 5
  LOCK_WINDOW = 15.minutes

  # Google Authenticator Setup
  MFA_STEP_SECONDS = 30
  MFA_DIGITS = 6
  MFA_DRIFT_STEPS = 1
  MFA_LOCK_LIMIT = 5
  MFA_LOCK_WINDOW = 15.minutes

  # Basic account validation rules
  validates :username,
            presence: { message: "cant be blank" },
            uniqueness: { case_sensitive: false },
            length: { minimum: USERNAME_MIN, maximum: USERNAME_MAX },
            format: {
              with: /\A[A-Za-z0-9._-]+\z/,
              message: "can only contain letters, numbers, dots, underscores or dashes"
            }

  validates :country_code, presence: { message: "cant be blank" }
  validate :username_should_not_look_like_email
  validate :username_should_not_contain_spaces
  validate :revolut_tag_required_on_create, on: :create
  validate :revolut_tag_format, if: -> { revolut_tag.present? }
  validate :password_complexity, if: :password
  validate :password_not_include_username, if: :password

  # Decrypts the stored Revolut tag when it is needed by the app
  def revolut_tag
    return nil if revolut_tag_encrypted.blank?

    self.class.revolut_tag_encryptor.decrypt_and_verify(revolut_tag_encrypted)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  # Normalises and encrypts the Revolut tag before saving it
  def revolut_tag=(plain)
    cleaned = plain.to_s.strip

    if cleaned.present?
      cleaned = "@#{cleaned}" unless cleaned.start_with?("@")
      self.revolut_tag_encrypted = self.class.revolut_tag_encryptor.encrypt_and_sign(cleaned)
    else
      self.revolut_tag_encrypted = nil
    end
  end

  # Returns true while the login lockout window is still active
  def locked?
    locked_at.present? && locked_at > LOCK_WINDOW.ago
  end

  # Tracks failed login attempts and locks the account after too many failures
  def register_failed_login!
    n = (failed_attempts || 0) + 1
    security_update!(
      failed_attempts: n,
      locked_at: (n >= LOCK_LIMIT ? Time.current : locked_at)
    )
  end

  # Clears failed login attempts after a successful login
  def reset_failed_logins!
    security_update!(
      failed_attempts: 0,
      locked_at: nil
    )
  end

  # Returns true while the Google Authenticator lockout window is still active
  def mfa_locked?
    mfa_locked_at.present? && mfa_locked_at > MFA_LOCK_WINDOW.ago
  end

  # Creates a Google Authenticator secret if the user does not already have one
  def create_secret
    return if mfa_secret.present?

    self.mfa_secret = self.class.generate_mfa_secret
    security_update!(mfa_secret_encrypted: mfa_secret_encrypted)
  end

  # Decrypts the Google Authenticator secret used to verify codes
  def mfa_secret
    return nil if mfa_secret_encrypted.blank?

    self.class.mfa_encryptor.decrypt_and_verify(mfa_secret_encrypted)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  # Encrypts the Google Authenticator secret before storing it in the database
  def mfa_secret=(plain)
    if plain.present?
      self.mfa_secret_encrypted = self.class.mfa_encryptor.encrypt_and_sign(plain)
    else
      self.mfa_secret_encrypted = nil
    end
  end

  # Verifies the submitted Google Authenticator code
  def verify_mfa_code!(code)
    return false if mfa_locked?

    c = code.to_s.gsub(/\s+/, "")
    return register_mfa_failure! && false unless c.match?(/\A\d{#{MFA_DIGITS}}\z/)

    step_now = Time.current.to_i / MFA_STEP_SECONDS
    last = mfa_last_used_step || -1

    matched_step = nil

    (step_now - MFA_DRIFT_STEPS).upto(step_now + MFA_DRIFT_STEPS) do |st|
      next if st <= last

      if self.class.totp_for_secret(mfa_secret, st) == c
        matched_step = st
        break
      end
    end

    if matched_step
      security_update!(
        mfa_last_used_step: matched_step,
        mfa_failed_attempts: 0,
        mfa_locked_at: nil
      )
      true
    else
      register_mfa_failure!
      false
    end
  end

  # Turns Google Authenticator MFA on after the first correct code
  def enable_mfa!(code)
    create_secret
    return false unless verify_mfa_code!(code)

    security_update!(mfa_enabled: true)
    true
  end

  # Clears Google Authenticator failed attempts and unlocks MFA entry
  def reset_mfa_lock!
    security_update!(
      mfa_failed_attempts: 0,
      mfa_locked_at: nil
    )
  end

  # Creates the encryptor used for Revolut tag storage
  def self.revolut_tag_encryptor
    key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key("revolut_tag_v1", 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm")
  end

  # Creates the encryptor used for Google Authenticator secret storage
  def self.mfa_encryptor
    key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key("mfa_secret_v1", 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm")
  end

  # Generating Secret (BASE32)
  def self.generate_mfa_secret
    base32_encode(SecureRandom.random_bytes(20))
  end

  # Creates the expected 6-digit Google Authenticator code for a given secret and time step
  def self.totp_for_secret(secret_base32, step)
    return nil if secret_base32.blank?

    key = base32_decode(secret_base32)
    msg = [ step ].pack("Q>")
    hmac = OpenSSL::HMAC.digest("sha1", key, msg)
    bytes = hmac.bytes
    offset = bytes[-1] & 0x0f
    part = bytes[offset, 4]
    bin = ((part[0] & 0x7f) << 24) | (part[1] << 16) | (part[2] << 8) | part[3]

    (bin % (10**MFA_DIGITS)).to_s.rjust(MFA_DIGITS, "0")
  end

  # Converts random bytes into the BASE32 format expected by Google Authenticator
  def self.base32_encode(data)
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    buffer = 0
    bits_left = 0
    out = +""

    data.each_byte do |b|
      buffer = (buffer << 8) | b
      bits_left += 8

      while bits_left >= 5
        bits_left -= 5
        out << alphabet[(buffer >> bits_left) & 31]
      end
    end

    if bits_left > 0
      out << alphabet[(buffer << (5 - bits_left)) & 31]
    end

    out
  end

  # Converts a BASE32 Google Authenticator secret back into bytes for checking codes
  def self.base32_decode(str)
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    map = {}
    alphabet.chars.each_with_index { |ch, i| map[ch] = i }
    buffer = 0
    bits_left = 0
    out = +""

    str.to_s.upcase.each_char do |ch|
      v = map[ch]
      next if v.nil?

      buffer = (buffer << 5) | v
      bits_left += 5

      if bits_left >= 8
        bits_left -= 8
        out << ((buffer >> bits_left) & 0xff).chr
      end
    end

    out
  end

  private

  # Updates login and MFA security fields without re-validating older accounts
  def security_update!(attrs)
    attrs[:updated_at] = Time.current if has_attribute?(:updated_at)
    update_columns(attrs)
  end

  # Tracks failed Google Authenticator attempts and locks MFA after too many failures
  def register_mfa_failure!
    n = (mfa_failed_attempts || 0) + 1
    security_update!(
      mfa_failed_attempts: n,
      mfa_locked_at: (n >= MFA_LOCK_LIMIT ? Time.current : mfa_locked_at)
    )
    true
  end

  # Stops usernames from being email addresses or contact details
  def username_should_not_look_like_email
    return if username.blank?

    errors.add(:username, "must not be an email address") if username.include?("@")
  end

  # Stops users from entering full-name style usernames with spaces
  def username_should_not_contain_spaces
    return if username.blank?

    errors.add(:username, "must not contain spaces") if username.match?(/\s/)
  end

  # Requires a Revolut tag when creating a new account
  def revolut_tag_required_on_create
    errors.add(:revolut_tag, "is required") if revolut_tag.blank?
  end

  # Keeps Revolut tags in a consistent @username format
  def revolut_tag_format
    unless revolut_tag.match?(/\A@[A-Za-z0-9._-]{3,30}\z/)
      errors.add(:revolut_tag, "must start with @ and contain 3-30 letters, numbers, dots, underscores or dashes")
    end
  end

  # Enforces stronger password rules than the Rails default
  def password_complexity
    return if password.blank?

    too_short = password.length < PASSWORD_MIN
    too_long = password.length > PASSWORD_MAX
    no_upper = password !~ /[A-Z]/
    no_lower = password !~ /[a-z]/
    no_digit = password !~ /\d/
    no_symbol = password !~ /[^A-Za-z0-9]/

    errors.add(:password, "must be at least #{PASSWORD_MIN} characters") if too_short
    errors.add(:password, "must be no more than #{PASSWORD_MAX} characters") if too_long
    errors.add(:password, "must include uppercase, lowercase, number and symbol") if no_upper || no_lower || no_digit || no_symbol
  end

  # Stops users from putting their username inside their password
  def password_not_include_username
    return if password.blank? || username.blank?

    errors.add(:password, "cannot contain your username") if password.downcase.include?(username.downcase)
  end
end
