require "rails_helper"

RSpec.describe Detection::Run do
  before { Merchants::Catalogue.sync! }

  let(:household) { create_household }

  def upi(slug, name, vpa, rupees, on)
    ref = (on.jd * 7919) % 10**12
    [ SyntheticSbi::Txn.new(on, "WDL TFR UPI/DR/#{ref}/#{name}/YESB/#{vpa}/Payment 00976#{ref % 10**8} AT 09482 BIDHANNAGAR", -rupees * 100),
      slug ]
  end

  # Imports a statement, then pins each row's merchant, so the spec doesn't
  # depend on the resolver.
  def import!(target, rows)
    text = SyntheticSbi.render(rows: rows.map(&:first).sort_by(&:posted_on), opening_paise: 500_000_00, from: Date.new(2026, 1, 1),
      to: Date.new(2026, 9, 30), account_number: "3948102#{target.id.to_s.rjust(4, "0")}")
    import = Statements::Importer.import_text(household: target, text: text, filename: "s.pdf")
    expect(import.status).to eq("imported")
    slugs = rows.to_h { |txn, slug| [ [ txn.posted_on, txn.amount_paise ], slug ] }
    target.bank_transactions.each do |txn|
      merchant = Merchant.find_by!(slug: slugs.fetch([ txn.posted_on, txn.amount_paise ]))
      txn.update_columns(merchant_id: merchant.id, counterparty: "merchant", resolution: "rule", resolved_at: Time.current)
    end
  end

  let(:txns) do
    months = (0..8).map { |k| Date.new(2026, 1, 5) >> k }
    months.each_with_index.map { |on, k| upi("netflix", "NETFLIX", "netflix@icici", k < 5 ? 499 : 649, on) } +
      months.map { |on| upi("spotify", "SPOTIFY INDIA", "spotify@axisbank", 119, on + 6) } +
      months.zip([ 1840, 2210, 1620, 1415, 1990, 2475, 2390, 1760, 1530 ])
        .map { |on, rupees| upi("msedcl", "MSEDCL", "msedcl@sbi", rupees, on + 9) }
  end

  it "stores series, their charges and findings that point at the evidence" do
    import!(household, txns)
    result = described_class.new(household: household).call

    netflix = household.recurring_series.joins(:merchant).find_by!(merchants: { slug: "netflix" })
    expect(netflix).to have_attributes(cadence: "monthly", status: "active", flagged: true, amount_paise: 649_00,
      monthly_cost_paise: 649_00, charges_count: 9, first_charged_on: Date.new(2026, 1, 5), last_charged_on: Date.new(2026, 9, 5),
      next_expected_on: Date.new(2026, 10, 5))
    expect(netflix.series_charges.map(&:level)).to eq([ 0 ] * 5 + [ 1 ] * 4)
    expect(netflix.bank_transactions.map(&:amount_paise).uniq).to eq([ -499_00, -649_00 ])

    increase = household.findings.kind_price_increase.sole
    expect(increase).to have_attributes(recurring_series: netflix, previous_amount_paise: 499_00, amount_paise: 649_00)
    expect(increase.step_transaction).to have_attributes(posted_on: Date.new(2026, 6, 5), amount_paise: -649_00)

    subscriptions = household.findings.kind_subscription.map { |finding| finding.recurring_series.merchant.slug }
    expect(subscriptions).to contain_exactly("netflix", "spotify")
    expect(household.recurring_series.flagged.count).to eq(2)
    expect(result.findings.size).to eq(3)
  end

  it "replaces earlier results and leaves other households alone" do
    other = create_household(name: "Other")
    import!(other, txns.first(9))
    described_class.new(household: other).call
    import!(household, txns)

    2.times { described_class.new(household: household).call }
    expect(household.recurring_series.flagged.count).to eq(2)
    expect(household.findings.count).to eq(3)
    expect(RecurringSeriesCharge.where(recurring_series: household.recurring_series.flagged).count).to eq(18)
    expect(other.recurring_series.count).to eq(1)
    expect(other.findings.kind_price_increase.count).to eq(1)
  end

  it "treats the latest transaction as now, so an old statement still has active series" do
    import!(household, txns)
    described_class.new(household: household).call
    expect(household.recurring_series.flagged.pluck(:status).uniq).to eq([ "active" ])
  end

  it "runs after every import" do
    expect { import!(household, txns) }.to have_enqueued_job(Detection::RunJob).with(household.id)
    expect { Detection::RunJob.perform_now(household.id) }.to change { household.findings.count }.from(0).to(3)
  end
end
