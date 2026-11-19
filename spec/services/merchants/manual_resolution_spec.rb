require "rails_helper"

RSpec.describe Merchants::ManualResolution do
  let(:household) { create_household }
  let(:youtube) { Merchant.find_by!(slug: "youtube_premium") }

  before { import_demo!(household) }

  it "learns the UPI ID as a household alias, resolves the matching rows and re-runs detection" do
    row = review_row(household, "GOOGLE PLAY")
    outcome = described_class.new(household: household).call(row, counterparty: "merchant", merchant: youtube)

    expect(outcome.learned).to have_attributes(household: household, kind: "vpa", pattern: "youtube.premium@okaxis",
      merchant: youtube)
    expect(outcome.also_resolved).to eq(9)
    expect(row.reload).to have_attributes(resolution: "manual", counterparty: "merchant", merchant: youtube)
    expect(household.bank_transactions.where(merchant: youtube).pluck(:resolution).tally).to eq("manual" => 1, "vpa_alias" => 9)
    expect(household.bank_transactions.needs_review.count).to eq(2)
    expect(finding_labels(household)).to include(%w[ subscription youtube_premium ])
  end

  it "teaches only this household" do
    row = review_row(household, "GOOGLE PLAY")
    described_class.new(household: household).call(row, counterparty: "merchant", merchant: youtube)

    expect(Merchants::Resolver.new(household: household).resolve(row.narration).merchant).to eq(youtube)
    expect(Merchants::Resolver.new(household: create_household(name: "Other")).resolve(row.narration)).to be_abstained
  end

  it "settles a person, bank or cash answer on that row alone" do
    row = review_row(household, "SAI KRUPA")
    expect { described_class.new(household: household).call(row, counterparty: "person") }
      .not_to change { household.findings.pluck(:id) }

    expect(row.reload).to have_attributes(resolution: "manual", counterparty: "person", merchant: nil)
    expect(household.bank_transactions.needs_review.count).to eq(11)
    expect(MerchantAlias.where(household: household)).to be_empty
  end
end
