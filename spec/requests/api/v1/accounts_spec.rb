require "rails_helper"

RSpec.describe "API v1 accounts" do
  let(:user) { create_user }
  let(:household) { user.household }

  it "requires a session" do
    get api_v1_accounts_path, as: :json
    assert_response_schema_confirm(401)
  end

  it "lists only the current household's accounts with balances in paise" do
    bank = create_account(household, name: "SBI Savings", kind: "asset")
    netflix = create_account(household, name: "Netflix", kind: "expense")
    create_account(household, name: "Unused", kind: "expense")
    Ledger.post!(household: household, occurred_on: Date.new(2026, 11, 3), memo: "NETFLIX",
      lines: [ [ netflix, 649_00 ], [ bank, -649_00 ] ])

    other = create_household(name: "Neighbours")
    create_account(other, name: "Their bank", kind: "asset")

    sign_in(user)
    get api_v1_accounts_path, as: :json

    assert_response_schema_confirm(200)
    expect(json["accounts"]).to eq([
      { "id" => bank.id, "name" => "SBI Savings", "kind" => "asset", "balance_paise" => -649_00 },
      { "id" => netflix.id, "name" => "Netflix", "kind" => "expense", "balance_paise" => 649_00 },
      { "id" => household.accounts.find_by!(name: "Unused").id, "name" => "Unused", "kind" => "expense", "balance_paise" => 0 }
    ])
  end
end
