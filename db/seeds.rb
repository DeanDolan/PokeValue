if User.find_by(username: "Dola").nil?
  u = User.new(
    username: "Dola",
    country_code: "IE",
    recovery_question: "What city were you born in?",
    password: "Dola_Secure!Pass123",
    password_confirmation: "Dola_Secure!Pass123"
  )
  u.recovery_answer = "Dublin"
  u.admin = true
  u.save!
  puts "Seeded admin: Dola"
end

Product.find_or_create_by!(sku: "ETB-SCARLET") do |p|
  p.name = "Scarlet & Violet ETB"
  p.image = "https://example.com/etb.jpg"
  p.era = "Scarlet & Violet"
  p.set_name = "Base Set"
  p.product_type = "Elite Trainer Box"
  p.value = 59.99
end
