require "rails_helper"

RSpec.describe Synthetic::Narrations do
  let(:examples) { described_class.new(seed: 99).examples(400) }

  it "is reproducible from its seed" do
    expect(described_class.new(seed: 99).examples(50)).to eq(examples.first(50))
    expect(described_class.new(seed: 100).examples(50)).not_to eq(examples.first(50))
  end

  it "labels every example with a catalogue slug or a counterparty kind" do
    slugs = Merchants::Catalogue.entries.map(&:slug)
    expect(examples.map(&:label) - slugs - %w[ unknown person bank cash ]).to eq([])
    expect(described_class::MERCHANTS.keys - slugs).to eq([])
    expect(examples.map(&:label).tally.keys).to include("unknown", "person", "bank", "cash")
  end

  it "damages narrations the way statements do" do
    expect(examples.flat_map(&:noise).tally.keys).to include("payee truncated", "UPI ID without domain", "UPI ID truncated")
    expect(examples.map(&:narration)).to all(satisfy { |n| n.split(" ").all? { |word| word.length <= described_class::WRAP } })
    expect(examples.map(&:amount_paise)).to all(be_an(Integer).and(satisfy(&:nonzero?)))
  end

  it "produces narrations the statement parser and importer accept" do
    txns = examples.first(30).each_with_index.map do |example, index|
      SyntheticSbi::Txn.new(Date.new(2026, 11, 1) + (index / 3), example.narration, example.amount_paise)
    end
    text = SyntheticSbi.render(rows: txns, opening_paise: 10_00_000_00, from: Date.new(2026, 11, 1), to: Date.new(2026, 11, 30))
    statement = Statements.parser_for(text).parse(text)
    expect(statement.rows.map(&:narration)).to eq(txns.map(&:narration))
  end
end
