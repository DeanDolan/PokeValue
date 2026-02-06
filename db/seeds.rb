admin_username = "Dola"

if User.find_by(username: admin_username).nil?
  pw = ENV["ADMIN_PASSWORD"].to_s
  if pw.blank?
    pw = SecureRandom.base64(24).gsub(/[^A-Za-z0-9]/, "").slice(0, 18) + "!"
  end

  u = User.new(
    username: admin_username,
    country_code: "IE",
    recovery_question: "What hospital were you born in?",
    password: pw,
    password_confirmation: pw,
    admin: true,
    failed_attempts: 0
  )
  u.recovery_answer = "Rotunda Hospital"
  u.save!
  puts "Seeded admin: #{admin_username}"
  puts "Admin password: #{pw}" if ENV["ADMIN_PASSWORD"].blank?
end

Product.find_or_create_by!(sku: "ETB-SCARLET") do |p|
  p.name = "Scarlet & Violet ETB"
  p.image = "https://example.com/etb.jpg"
  p.era = "Scarlet & Violet"
  p.set_name = "Base Set"
  p.product_type = "Elite Trainer Box"
  p.value = 59.99
end
