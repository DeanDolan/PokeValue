class User < ApplicationRecord
  has_secure_password
  has_many :holdings, dependent: :destroy
  has_many :watchlists, dependent: :destroy

  USERNAME_MIN = 4
  PASSWORD_MIN = 12
  LOCK_LIMIT = 5
  LOCK_WINDOW = 15.minutes

  MFA_STEP_SECONDS = 30
  MFA_DIGITS = 6
  MFA_DRIFT_STEPS = 1
  MFA_LOCK_LIMIT = 5
  MFA_LOCK_WINDOW = 15.minutes
  MFA_RECOVERY_CODES_COUNT = 10

  validates :username, presence: true, uniqueness: true, length: { minimum: USERNAME_MIN }
  validates :country_code, presence: true
  validate :password_complexity, if: :password
  validate :password_not_include_username, if: :password

  def recovery_answer=(plain)
    self.recovery_answer_digest = BCrypt::Password.create(plain) if plain.present?
  end

  def recovery_answer_matches?(plain)
    return false if recovery_answer_digest.blank? || plain.blank?
    BCrypt::Password.new(recovery_answer_digest) == plain
  end

  def locked?
    locked_at.present? && locked_at > LOCK_WINDOW.ago
  end

  def register_failed_login!
    n = (failed_attempts || 0) + 1
    update!(failed_attempts: n, locked_at: (n >= LOCK_LIMIT ? Time.current : locked_at))
  end

  def reset_failed_logins!
    update!(failed_attempts: 0, locked_at: nil)
  end

  def mfa_locked?
    mfa_locked_at.present? && mfa_locked_at > MFA_LOCK_WINDOW.ago
  end

  def ensure_mfa_secret!
    return if mfa_secret.present?
    self.mfa_secret = self.class.generate_mfa_secret
    save!
  end

  def mfa_secret
    return nil if mfa_secret_encrypted.blank?
    self.class.mfa_encryptor.decrypt_and_verify(mfa_secret_encrypted)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  def mfa_secret=(plain)
    if plain.present?
      self.mfa_secret_encrypted = self.class.mfa_encryptor.encrypt_and_sign(plain)
    else
      self.mfa_secret_encrypted = nil
    end
  end

  def mfa_provisioning_uri(issuer: "PokeValueApp")
    s = mfa_secret
    return nil if s.blank?
    label = "#{issuer}:#{username}"
    "otpauth://totp/#{CGI.escape(label)}?secret=#{s}&issuer=#{CGI.escape(issuer)}&algorithm=SHA1&digits=#{MFA_DIGITS}&period=#{MFA_STEP_SECONDS}"
  end

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
      update!(mfa_last_used_step: matched_step, mfa_failed_attempts: 0, mfa_locked_at: nil)
      true
    else
      register_mfa_failure!
      false
    end
  end

  def enable_mfa!(code)
    ensure_mfa_secret!
    return nil unless verify_mfa_code!(code)
    update!(mfa_enabled: true)
    generate_mfa_recovery_codes!
  end

  def mfa_recovery_codes_digests
    raw = mfa_recovery_codes_digest.to_s
    return [] if raw.blank?
    JSON.parse(raw)
  rescue JSON::ParserError
    []
  end

  def generate_mfa_recovery_codes!
    codes = Array.new(MFA_RECOVERY_CODES_COUNT) { self.class.generate_recovery_code }
    digests = codes.map { |c| BCrypt::Password.create(c) }
    update!(mfa_recovery_codes_digest: digests.to_json)
    codes
  end

  def consume_mfa_recovery_code!(code)
    c = code.to_s.strip.upcase
    return false if c.blank?
    digests = mfa_recovery_codes_digests
    return false if digests.empty?

    idx = digests.find_index do |d|
      BCrypt::Password.new(d) == c
    rescue BCrypt::Errors::InvalidHash
      false
    end

    return false if idx.nil?
    digests.delete_at(idx)
    update!(mfa_recovery_codes_digest: digests.to_json)
    true
  end

  def reset_mfa_lock!
    update!(mfa_failed_attempts: 0, mfa_locked_at: nil)
  end

  def self.mfa_encryptor
    key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key("mfa_secret_v1", 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm")
  end

  def self.generate_mfa_secret
    base32_encode(SecureRandom.random_bytes(20))
  end

  def self.generate_recovery_code
    SecureRandom.hex(5).upcase
  end

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

  def register_mfa_failure!
    n = (mfa_failed_attempts || 0) + 1
    update!(mfa_failed_attempts: n, mfa_locked_at: (n >= MFA_LOCK_LIMIT ? Time.current : mfa_locked_at))
    true
  end

  def password_complexity
    return if password.blank?
    too_short = password.length < PASSWORD_MIN
    no_upper = password !~ /[A-Z]/
    no_lower = password !~ /[a-z]/
    no_digit = password !~ /\d/
    no_symbol = password !~ /[^A-Za-z0-9]/
    errors.add(:password, "must be at least #{PASSWORD_MIN} chars") if too_short
    errors.add(:password, "must include upper, lower, digit, symbol") if no_upper || no_lower || no_digit || no_symbol
  end

  def password_not_include_username
    return if password.blank? || username.blank?
    errors.add(:password, "cannot contain your username") if password.downcase.include?(username.downcase)
  end
end
