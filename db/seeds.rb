# Synthetic demo data only. Real statements never go in seeds, fixtures or git.
#
#   bin/rails db:seed
#   DEMO_PASSWORD=... bin/rails db:seed   # choose the demo password

# The merchant catalogue is reference data, not demo data, so it is synced
# everywhere (config/merchants.yml).
Merchants::Catalogue.sync!

return if Rails.env.production? && ENV["ALLOW_DEMO_SEED"] != "1"

household = Household.find_or_create_by!(name: "Demo household")

password = ENV.fetch("DEMO_PASSWORD") do
  raise "Set DEMO_PASSWORD to seed outside development" unless Rails.env.local?
  "demo-password-change-me"
end
User.find_or_create_by!(email_address: "demo@leak.test") do |user|
  user.household = household
  user.password = password
end

# A year of a fabricated SBI statement (lib/synthetic/demo_statement.rb),
# imported like an uploaded one, then detection run straight away rather
# than by the background job the import enqueues.
if household.bank_transactions.none?
  import = Statements::Importer.import_text(household: household, text: Synthetic::DemoStatement.text,
    filename: "demo-statement.pdf")
  raise "Demo statement didn't import: #{import.error_message}" if import.rejected?

  Detection::Run.new(household: household).call
end

puts "Seeded #{household.name}: sign in as demo@leak.test"
