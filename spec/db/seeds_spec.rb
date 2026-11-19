require "rails_helper"

RSpec.describe "db/seeds.rb" do
  it "creates the demo household with a year of statements and its findings, once" do
    expect { Rails.application.load_seed }.to output(/demo@leak\.test/).to_stdout
    household = User.find_by!(email_address: "demo@leak.test").household
    expect(household.bank_transactions.count).to eq(Synthetic::DemoStatement.txns.size)
    expect(household.findings.kind_price_increase.count).to eq(1)

    expect { Rails.application.load_seed }.to output.to_stdout
    expect(household.bank_transactions.count).to eq(Synthetic::DemoStatement.txns.size)
  end
end
