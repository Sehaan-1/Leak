# Synthetic demo data only. Real statements never go in seeds, fixtures or git.
#
#   bin/rails db:seed
#   DEMO_PASSWORD=... bin/rails db:seed   # choose the demo password

# The merchant catalogue is reference data, not demo data, so it is synced
# everywhere (config/merchants.yml).
Merchants::Catalogue.sync!

return if Rails.env.production? && ENV["ALLOW_DEMO_SEED"] != "1"

password = ENV.fetch("DEMO_PASSWORD") do
  raise "Set DEMO_PASSWORD to seed outside development" unless Rails.env.local?
  "demo-password-change-me"
end
# Found by its user: public demo visitors' households have the same name.
user = User.find_by(email_address: "demo@leak.test") ||
  Household.create!(name: "Demo household").users.create!(email_address: "demo@leak.test", password: password)
household = user.household

# A year of a fabricated SBI statement (lib/synthetic/demo_statement.rb),
# imported like an uploaded one, then run through detection.
Demo.populate!(household) if household.bank_transactions.none?

puts "Seeded #{household.name}: sign in as demo@leak.test"
