# Sets the username for the test admin account.
admin_username = "Dola4"

# Only creates the admin if it does not already exist.
if User.find_by(username: admin_username).nil?
  # Reads the password from the PowerShell ADMIN_PASSWORD value.
  pw = ENV["ADMIN_PASSWORD"].to_s

  # Stops the seed from creating the admin with a blank password.
  if pw.blank?
    raise "ADMIN_PASSWORD is required. Run: $env:ADMIN_PASSWORD=\"TestPassword1!\""
  end

  # Creates the test admin account.
  u = User.new(
    username: admin_username,
    country_code: "IE",
    revolut_tag: "@dola4",
    password: pw,
    password_confirmation: pw,
    admin: true,
    failed_attempts: 0,
    locked_at: nil,
    mfa_enabled: false,
    mfa_secret_encrypted: nil,
    mfa_last_used_step: nil,
    mfa_failed_attempts: 0,
    mfa_locked_at: nil,
    mfa_recovery_codes_digest: nil
  )

  # Saves the admin to the users table.
  u.save!

  # Prints confirmation in the terminal.
  puts "Seeded admin: #{admin_username}"
end
