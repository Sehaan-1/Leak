require "rails_helper"

RSpec.describe "API v1 bank transactions" do
  let(:user) { create_user }

  it "requires a session" do
    get api_v1_bank_transactions_path, as: :json
    assert_response_schema_confirm(401)
  end

  it "lists the household's statement lines newest first, decrypted" do
    Statements::Importer.import_text(household: user.household, text: sample_text, filename: "s.pdf")
    sign_in(user)

    get api_v1_bank_transactions_path, as: :json

    assert_response_schema_confirm(200)
    rows = json["bank_transactions"]
    expect(rows.size).to eq(7)
    expect(rows.first).to include("posted_on" => "2026-11-15", "amount_paise" => -1_825_00,
      "balance_after_paise" => 24_850_75, "ref" => nil, "bank_account" => include("name" => "SBI ••9475"))
    expect(rows.first["narration"]).to start_with("WDL TFR UPI/DR/631954012938/FRESH HARVEST")
    expect(rows.last).to include("posted_on" => "2026-11-01", "amount_paise" => 15_000_00)
    # Same-day rows keep statement order (newest first): row 2 before row 1 on 01/11.
    expect(rows.last(2).map { |r| r["balance_after_paise"] }).to eq([ 26_204_75, 27_450_25 ])
    expect(json["next_page"]).to be_nil
  end

  it "paginates" do
    stub_const("Api::V1::BankTransactionsController::PER_PAGE", 3)
    Statements::Importer.import_text(household: user.household, text: sample_text, filename: "s.pdf")
    sign_in(user)

    get api_v1_bank_transactions_path(page: 3), as: :json

    assert_response_schema_confirm(200)
    expect(json["bank_transactions"].size).to eq(1)
    expect(json["next_page"]).to be_nil

    get api_v1_bank_transactions_path(page: 1), as: :json
    expect(json["next_page"]).to eq(2)
  end

  it "doesn't show other households' transactions" do
    Statements::Importer.import_text(household: create_household(name: "Neighbours"), text: sample_text, filename: "x.pdf")
    sign_in(user)
    get api_v1_bank_transactions_path, as: :json
    expect(json["bank_transactions"]).to eq([])
  end
end
