require "rails_helper"

RSpec.describe Synthetic::DemoStatement do
  let(:household) { create_household }

  before { import_demo!(household) }

  it "imports as one reconciled statement" do
    expect(household.statement_imports.sole).to have_attributes(status: "imported", rows_count: described_class.txns.size)
    expect(household.bank_transactions.count).to eq(described_class.txns.size)
  end

  it "gives detection a price increase, a duplicate and four subscriptions" do
    expect(finding_labels(household)).to contain_exactly(
      %w[ subscription netflix ], %w[ subscription spotify ], %w[ subscription jiohotstar ], %w[ subscription jiohotstar ],
      %w[ price_increase netflix ], %w[ duplicate jiohotstar ]
    )
    increase = household.findings.kind_price_increase.sole
    expect(increase).to have_attributes(previous_amount_paise: 499_00, amount_paise: 649_00)
    expect(increase.step_transaction.posted_on).to eq(Date.new(2026, 7, 5))
    duplicate = household.findings.kind_duplicate.sole
    expect(duplicate.recurring_series.amount_paise).to eq(149_00)
    expect(duplicate.related_series.amount_paise).to eq(299_00)
  end

  it "leaves YouTube Premium billed through Google Play, and an unknown shop, for review" do
    vpas = household.bank_transactions.needs_review.map { |txn| Merchants::Narration.parse(txn.narration).vpa }
    expect(vpas.tally).to eq("youtube.premium@okaxis" => 10, "q482915736@ybl" => 2)
  end
end
