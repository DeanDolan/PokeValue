# Seeds the first admin account used to manage the application.
admin_username = "Dola"

# Only creates the admin if it does not already exist.
if User.find_by(username: admin_username).nil?
  # Uses an environment variable for the admin password when available.
  pw = ENV["ADMIN_PASSWORD"].to_s

  # Creates a temporary strong password if ADMIN_PASSWORD has not been set.
  if pw.blank?
    pw = SecureRandom.base64(24).gsub(/[^A-Za-z0-9]/, "").slice(0, 18) + "!"
  end

  # Builds the admin user with Irish country details and admin privileges.
  u = User.new(
    username: admin_username,
    country_code: "IE",
    recovery_question: "What hospital were you born in?",
    password: pw,
    password_confirmation: pw,
    admin: true,
    failed_attempts: 0
  )

  # Stores the recovery answer before saving the admin account.
  u.recovery_answer = "Rotunda Hospital"
  u.save!

  # Prints confirmation in the Rails console after seeding.
  puts "Seeded admin: #{admin_username}"

  # Shows the generated password only when no ADMIN_PASSWORD was supplied.
  puts "Admin password: #{pw}" if ENV["ADMIN_PASSWORD"].blank?
end

# Creates a starter sealed product record for testing product values and portfolio features.
Product.find_or_create_by!(sku: "ETB-SCARLET") do |p|
  p.name = "Scarlet & Violet ETB"
  p.image = "https://example.com/etb.jpg"
  p.era = "Scarlet & Violet"
  p.set_name = "Base Set"
  p.product_type = "Elite Trainer Box"
  p.value = 59.99
end
