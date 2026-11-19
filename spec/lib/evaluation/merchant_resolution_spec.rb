require "rails_helper"

RSpec.describe Evaluation::MerchantResolution do
  let(:answers) { {} }
  let(:resolver) do
    lookup = answers
    result = Data.define(:label, :via, :evidence)
    Class.new { define_method(:resolve) { |narration, **| result.new(lookup.fetch(narration), "rule", "fake") } }.new
  end

  def example(narration, label, channel: "upi") = { id: narration, narration: narration, amount_paise: -100, label: label, channel: channel }

  it "computes Wilson score intervals" do
    expect(described_class.wilson(0, 0)).to include(value: nil)
    expect(described_class.wilson(50, 100)).to include(value: 0.5, low: 0.4038, high: 0.5962)
    expect(described_class.wilson(300, 300)).to include(value: 1.0, low: 0.9874, high: 1.0)
  end

  it "scores merchant accuracy at coverage over business rows only" do
    answers.merge!("a" => "netflix", "b" => "swiggy", "c" => "abstain", "d" => "zomato", "e" => "person", "f" => "bank", "g" => "abstain")
    rows = [ example("a", "netflix"), example("b", "zomato"), example("c", "netflix"), example("d", "unknown"),
             example("e", "person"), example("f", "bank"), example("g", "cash", channel: "cash") ]
    report = described_class.new(rows, resolver: resolver).report

    expect(report.merchant).to include(rows: 4, answered: 3, correct: 1)
    expect(report.merchant[:coverage][:value]).to eq(0.75)
    expect(report.merchant[:accuracy][:value]).to eq(0.3333)
    expect(report.overall).to include(rows: 7, answered: 5, correct: 3)
    expect(report.catalogue_recall).to include(value: 0.3333, n: 3)
    expect(report.errors.map(&:id)).to eq(%w[ b d ])
    expect(report.by_channel["cash"]).to eq(n: 1, answered: 0, correct: 0)
    expect(report.gate_failures("merchant_accuracy_low" => 0.9, "merchant_coverage" => 0.5))
      .to contain_exactly(a_string_starting_with("merchant accuracy 95% lower bound"))
    expect(report.gate_failures("merchant_accuracy_low" => 0.0, "merchant_coverage" => 0.8))
      .to contain_exactly("merchant coverage 75.0% < 80.0%")
  end
end
