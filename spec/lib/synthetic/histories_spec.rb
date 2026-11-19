require "rails_helper"

RSpec.describe Synthetic::Histories do
  let(:histories) { described_class.new(seed: 11).histories(8) }
  let(:roles) { %w[ charge noise refund mandate reversal trial ] }

  it "is reproducible from its seed" do
    expect(described_class.new(seed: 11).histories(8).map(&:to_json)).to eq(histories.map(&:to_json))
    expect(described_class.new(seed: 12).histories(1).first.to_json).not_to eq(histories.first.to_json)
  end

  it "writes well-formed, dated, labelled transactions inside each history's window" do
    catalogue = Merchants::Catalogue.entries.to_h { [ _1.slug, _1.category ] }
    histories.each do |history|
      ids = history.txns.map(&:first)
      expect(ids).to eq((1..ids.size).to_a)
      expect(history.txns.map { _1[3] }).to eq(history.txns.map { _1[3] }.sort)
      expect(history.txns.map { _1[3] }.max).to be <= history.as_of
      history.txns.each do |_, merchant, category, _, amount, key, role|
        expect(catalogue.fetch(merchant)).to eq(category)
        expect(amount).to be_an(Integer).and(satisfy(&:nonzero?))
        expect(roles).to include(role)
        expect(key.nil? || history.series.key?(key)).to be(true)
        expect(role == "charge").to eq(!key.nil?)
      end
    end
  end

  it "labels subscriptions and commitments, and what a reader could detect" do
    series = histories.flat_map { _1.series.values }
    expect(series.map { _1[:kind] }.uniq).to contain_exactly("subscription", "commitment")
    expect(series.select { _1[:kind] == "commitment" }.map { _1[:detectable] }.uniq).to eq([ false ])
    series.select { _1[:detectable] }.each { expect(_1[:charges]).to be >= (_1[:cadence] == "annual" ? 2 : 3) }
  end

  it "includes the decoys the engine must reject" do
    many = described_class.new(seed: 5).histories(30)
    roles = many.flat_map { |history| history.txns.map(&:last) }.tally
    expect(roles.keys).to include("mandate", "reversal", "trial", "refund", "noise")
    expect(many.flat_map { _1.series.values }.count { _1[:increase] }).to be_positive
    expect(many.flat_map { _1.series.values }.count { _1[:duplicate_of] }).to be_positive
  end

  it "labels a price increase by the first charge at the new price" do
    history = described_class.new(seed: 5).histories(30).find { |h| h.series.values.any? { _1[:increase] } }
    key, info = history.series.find { |_, v| v[:increase] }
    charges = history.txns.select { _1[5] == key }
    step = charges.index { _1[0] == info[:increase][:txn] }
    expect(step).to be_positive
    expect(-charges[step][4]).to be > info[:increase][:previous_amount_paise]
    expect(-charges[step - 1][4]).to eq(info[:increase][:previous_amount_paise])
  end
end
