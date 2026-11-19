require "rails_helper"

RSpec.describe Detection::Engine do
  subject(:engine) { described_class.new(as_of: as_of) }

  let(:as_of) { Date.new(2026, 10, 31) }
  let(:categories) do
    { "netflix" => "streaming", "spotify" => "music", "openai" => "software", "jio" => "telecom", "hdfc_mf" => "investment",
      "bajaj_finance" => "loan", "nobroker" => "rent", "lic" => "insurance", "msedcl" => "utilities", "swiggy" => "food_delivery",
      "uber" => "transport", "times_prime" => "news", "google_play" => "software" }
  end

  def txns_for(merchant, entries)
    @id ||= 0
    entries.map { |on, rupees| Detection::Txn.new(@id += 1, merchant, categories.fetch(merchant), on.is_a?(Date) ? on : Date.parse(on), (rupees * 100).round) }
  end

  def monthly(merchant, from, count, rupees, day_jitter: [])
    start = Date.parse(from)
    txns_for(merchant, (0...count).map { |k| [ ((start >> k) + day_jitter.fetch(k, 0)).iso8601, -rupees ] })
  end

  it "finds a monthly subscription despite late charges and flags it" do
    result = engine.call(monthly("netflix", "2026-04-05", 7, 649, day_jitter: [ 0, 2, 0, 3, 1, 0, 2 ]))

    expect(result.series.size).to eq(1)
    series = result.series.first
    expect([ series.merchant, series.cadence.name, series.status, series.flagged, series.amount_paise ])
      .to eq([ "netflix", "monthly", "active", true, 649_00 ])
    expect(series.monthly_cost_paise).to eq(649_00)
    expect(result.findings.map(&:kind)).to eq(%w[ subscription ])
  end

  it "needs three monthly charges, and marks a series that stopped as ended without a finding" do
    expect(engine.call(monthly("spotify", "2026-08-10", 2, 119)).series).to be_empty

    result = engine.call(monthly("spotify", "2026-01-10", 4, 119))
    expect(result.series.first.status).to eq("ended")
    expect(result.findings).to be_empty
  end

  it "survives a missed renewal" do
    charges = monthly("spotify", "2026-03-10", 8, 119).reject.with_index { |_, k| k == 3 }
    expect(engine.call(charges).series.map { _1.charges.size }).to eq([ 7 ])
  end

  it "follows 28-day prepaid plans as monthly" do
    start = Date.new(2026, 1, 3)
    charges = txns_for("jio", (0...11).map { |k| [ (start + 28 * k).iso8601, -299 ] })
    series = engine.call(charges).series
    expect(series.map { [ _1.cadence.name, _1.charges.size ] }).to eq([ [ "monthly", 11 ] ])
  end

  it "finds annual subscriptions from two charges" do
    charges = txns_for("times_prime", [ [ "2025-02-14", -1199 ], [ "2026-02-16", -1199 ] ])
    series = engine.call(charges).series.first
    expect([ series.cadence.name, series.status, series.monthly_cost_paise ]).to eq([ "annual", "active", 99_92 ])
  end

  describe "price changes" do
    it "treats a new price where the next charge was due as a price step, with the evidence charge" do
      charges = monthly("netflix", "2026-01-05", 5, 499) + monthly("netflix", "2026-06-05", 5, 649)
      result = engine.call(charges)

      expect(result.series.size).to eq(1)
      series = result.series.first
      expect(series.levels.map { |level| level.map(&:amount_paise).uniq }).to eq([ [ 499_00 ], [ 649_00 ] ])
      increase = result.findings.find { _1.kind == "price_increase" }
      expect([ increase.previous_amount_paise, increase.amount_paise, increase.step_charge.on ])
        .to eq([ 499_00, 649_00, Date.new(2026, 6, 5) ])
      expect(result.findings.map(&:kind)).to contain_exactly("subscription", "price_increase")
    end

    it "waits for a second charge at the new price before calling it a step" do
      charges = monthly("netflix", "2026-04-05", 6, 499) + txns_for("netflix", [ [ "2026-10-05", -649 ] ])
      result = described_class.new(as_of: Date.new(2026, 10, 10)).call(charges)
      expect(result.findings.map(&:kind)).to eq(%w[ subscription ])
      expect(result.series.first.charges.size).to eq(6)
    end

    it "calls a second price running alongside the first a second subscription, not a step" do
      charges = monthly("netflix", "2026-01-05", 10, 499) + monthly("netflix", "2026-05-19", 6, 199)
      result = engine.call(charges)

      expect(result.series.map { [ _1.amount_paise, _1.charges.size ] }).to contain_exactly([ 499_00, 10 ], [ 199_00, 6 ])
      expect(result.findings.map(&:kind)).to contain_exactly("subscription", "subscription", "duplicate")
      duplicate = result.findings.find { _1.kind == "duplicate" }
      expect([ duplicate.series.amount_paise, duplicate.related.amount_paise ]).to eq([ 199_00, 499_00 ])
    end

    it "keeps two subscriptions at the same price apart" do
      charges = monthly("netflix", "2026-03-05", 8, 649) + monthly("netflix", "2026-05-20", 6, 649)
      series = engine.call(charges).series
      expect(series.map { _1.charges.map(&:on).map(&:day).uniq }).to contain_exactly([ 5 ], [ 20 ])
    end

    it "does not turn a second subscription into a step when the first one stops" do
      charges = monthly("netflix", "2026-01-05", 6, 499) + monthly("netflix", "2026-03-08", 8, 649)
      result = engine.call(charges)
      expect(result.series.map { _1.levels.size }).to eq([ 1, 1 ])
      expect(result.findings.map(&:kind)).not_to include("price_increase")
    end

    it "follows USD prices drifting with the exchange rate without calling it an increase" do
      rupees = [ 1712.4, 1698.2, 1730.9, 1745.0, 1721.3, 1760.8, 1779.5, 1752.1 ]
      charges = txns_for("openai", rupees.each_with_index.map { |r, k| [ (Date.new(2026, 3, 2) >> k).iso8601, -r ] })
      result = engine.call(charges)
      expect(result.series.map { _1.levels.size }).to eq([ 1 ])
      expect(result.findings.map(&:kind)).to eq(%w[ subscription ])
    end
  end

  describe "decoys" do
    it "keeps SIPs, EMIs, rent and insurance as unflagged commitments" do
      charges = monthly("hdfc_mf", "2026-01-10", 10, 2000) + monthly("bajaj_finance", "2026-01-03", 10, 3333) +
        monthly("nobroker", "2026-01-01", 10, 22_000) +
        txns_for("lic", [ [ "2026-01-28", -4712 ], [ "2026-04-28", -4712 ], [ "2026-07-28", -4712 ], [ "2026-10-28", -4712 ] ])
      result = engine.call(charges)

      expect(result.series.map(&:merchant)).to contain_exactly("hdfc_mf", "bajaj_finance", "nobroker", "lic")
      expect(result.series.map(&:flagged)).to all(be(false))
      expect(result.findings).to be_empty
    end

    it "never flags usage-priced utility bills" do
      rupees = [ 1840, 2210, 1620, 1415, 1388, 1990, 2475 ]
      charges = txns_for("msedcl", rupees.each_with_index.map { |r, k| [ (Date.new(2026, 4, 12) >> k).iso8601, -r ] })
      expect(engine.call(charges).findings).to be_empty
    end

    it "ignores ₹1 mandate set-ups and verifications" do
      charges = txns_for("spotify", [ [ "2026-06-01", -1 ], [ "2026-07-01", -1 ], [ "2026-08-01", -2 ], [ "2026-09-01", -1 ],
        [ "2026-10-01", -1 ] ])
      result = engine.call(charges)
      expect(result.series).to be_empty
      expect(result.mandates.size).to eq(5)
    end

    it "drops refunded charges, so reversed renewals are not a subscription" do
      charges = (0...4).flat_map do |k|
        on = Date.new(2026, 6, 9) >> k
        txns_for("netflix", [ [ on.iso8601, -649 ], [ (on + 1).iso8601, 649 ] ])
      end
      result = engine.call(charges)
      expect(result.series).to be_empty
      expect(result.refunded.size).to eq(4)
    end

    it "does not see a subscription in repeated orders and rides at the same price" do
      rng = Random.new(3)
      charges = (0...10).flat_map do |month|
        (0...8).map { [ (Date.new(2026, 1, 1) >> month) + rng.rand(0..27), -142 ] }
      end
      expect(engine.call(txns_for("uber", charges)).series).to be_empty
    end

    it "asks more of merchants where people mostly buy things" do
      expect(engine.call(monthly("swiggy", "2026-07-12", 3, 349)).series).to be_empty
      expect(engine.call(monthly("swiggy", "2026-05-12", 5, 349)).series.size).to eq(1)
    end

    it "finds an app subscription among in-app purchases at the same price" do
      subscription = monthly("google_play", "2026-02-03", 9, 99, day_jitter: [ 0, 1, 4, 0, 2, 0, 3, 0, 1 ])
      purchases = txns_for("google_play", [ [ "2026-03-20", -99 ], [ "2026-05-11", -49 ], [ "2026-07-25", -299 ] ])
      series = engine.call(subscription + purchases).series
      expect(series.map { [ _1.amount_paise, _1.charges.size ] }).to eq([ [ 99_00, 9 ] ])
    end
  end

  it "ignores transactions without a merchant" do
    charges = (0...5).map { |k| Detection::Txn.new(k + 1, nil, nil, Date.new(2026, 4, 1) >> k, -500_00) }
    expect(engine.call(charges).series).to be_empty
  end

  it "keeps each charge in at most one series" do
    charges = monthly("netflix", "2026-01-05", 10, 649) + monthly("netflix", "2026-01-12", 10, 649) +
      monthly("netflix", "2026-02-25", 8, 199)
    ids = engine.call(charges).series.flat_map { _1.charges.map(&:id) }
    expect(ids).to eq(ids.uniq)
    expect(ids.size).to eq(28)
  end
end
