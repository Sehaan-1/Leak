require "rails_helper"

RSpec.describe Evaluation::RecurringDetection do
  def history(txns, series)
    { "id" => "h-1", "as_of" => "2026-10-31", "txns" => txns, "series" => series }
  end

  def monthly(first_id, merchant, category, from, count, paise, key)
    (0...count).map { |k| [ first_id + k, merchant, category, (Date.parse(from) >> k).iso8601, -paise, key, key ? "charge" : "noise" ] }
  end

  let(:netflix) do
    { "netflix-1" => { "merchant" => "netflix", "kind" => "subscription", "cadence" => "monthly", "status" => "active",
                       "charges" => 6, "detectable" => true, "increase" => nil, "duplicate_of" => nil } }
  end

  it "scores a clean detection as perfect" do
    report = described_class.new([ history(monthly(1, "netflix", "streaming", "2026-05-05", 6, 649_00, "netflix-1"), netflix) ]).report
    expect(report.false_flags[:value]).to eq(0)
    expect(report.series_precision[:value]).to eq(1)
    expect(report.series_recall[:value]).to eq(1)
    expect(report.gate_failures("false_flags_per_100_high" => 50, "series_recall" => 0.9)).to eq([])
  end

  it "counts charges flagged outside a real subscription as false flags" do
    txns = monthly(1, "spotify", "music", "2026-05-10", 6, 119_00, nil)
    report = described_class.new([ history(txns, {}) ]).report
    expect(report.total(:false_flags)).to eq(6)
    expect(report.series_precision[:value]).to eq(0)
    expect(report.false_flag_roles).to eq("noise" => 6)
    expect(report.gate_failures("false_flags_per_100_high" => 1.0).first).to match(/false flags per 100 charges/)
    expect(report.error_lines.first).to match(/wrong series: spotify monthly active ₹119/)
  end

  it "counts a missed subscription against recall, and price increases by their evidence charge" do
    truth = netflix.merge("netflix-1" => netflix["netflix-1"].merge("increase" => { "previous_amount_paise" => 499_00, "txn" => 4 }))
    txns = monthly(1, "netflix", "streaming", "2026-02-05", 3, 499_00, "netflix-1") +
      monthly(4, "netflix", "streaming", "2026-05-05", 6, 649_00, "netflix-1")
    report = described_class.new([ history(txns, truth) ]).report
    expect([ report.increase_precision[:value], report.increase_recall[:value] ]).to eq([ 1, 1 ])

    missed = netflix.merge("spotify-1" => netflix["netflix-1"].merge("merchant" => "spotify"))
    report = described_class.new([ history(monthly(1, "netflix", "streaming", "2026-05-05", 6, 649_00, "netflix-1"), missed) ]).report
    expect(report.series_recall[:value]).to eq(0.5)
    expect(report.error_lines).to include(a_string_matching(/missed: spotify-1/))
  end

  it "rejects unknown gate keys" do
    expect { described_class.new([]).report.gate_failures("nope" => 1) }.to raise_error(ArgumentError, /nope/)
  end
end
