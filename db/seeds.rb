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

if household.journal_entries.none?
  accounts = {
    bank: household.accounts.find_or_create_by!(name: "SBI Savings", kind: "asset"),
    opening: household.accounts.find_or_create_by!(name: "Opening balances", kind: "equity"),
    netflix: household.accounts.find_or_create_by!(name: "Netflix", kind: "expense"),
    music: household.accounts.find_or_create_by!(name: "Music app", kind: "expense"),
    electricity: household.accounts.find_or_create_by!(name: "Electricity", kind: "expense")
  }
  household.suspense_account

  Ledger.post!(household: household, occurred_on: Date.new(2026, 8, 1), memo: "Opening balance",
    lines: [ [ accounts[:bank], 50_000_00 ], [ accounts[:opening], -50_000_00 ] ])

  # A subscription with a price step, an annual-cost leak, and a usage-priced bill (decoy).
  [ [ 8, 499_00 ], [ 9, 499_00 ], [ 10, 649_00 ], [ 11, 649_00 ] ].each do |month, paise|
    Ledger.post!(household: household, occurred_on: Date.new(2026, month, 5), memo: "NETFLIX.COM",
      lines: [ [ accounts[:netflix], paise ], [ accounts[:bank], -paise ] ])
  end
  (8..11).each do |month|
    Ledger.post!(household: household, occurred_on: Date.new(2026, month, 12), memo: "UPI-MUSICAPP",
      lines: [ [ accounts[:music], 199_00 ], [ accounts[:bank], -199_00 ] ])
  end
  [ [ 8, 1_840_00 ], [ 9, 2_210_00 ], [ 10, 1_975_00 ], [ 11, 1_390_00 ] ].each do |month, paise|
    Ledger.post!(household: household, occurred_on: Date.new(2026, month, 20), memo: "MSEDCL BILL",
      lines: [ [ accounts[:electricity], paise ], [ accounts[:bank], -paise ] ])
  end
end

puts "Seeded #{household.name}: sign in as demo@leak.test"
