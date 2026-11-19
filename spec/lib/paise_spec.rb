require "rails_helper"

RSpec.describe Paise do
  describe ".parse" do
    {
      "649" => 649_00,
      "649.00" => 649_00,
      "0.5" => 50,
      "0.05" => 5,
      "1,000" => 1_000_00,
      "12,345.67" => 12_345_67,
      "1,23,456.78" => 1_23_456_78,
      "12,34,56,789.01" => 12_34_56_789_01,
      "123,456.78" => 123_456_78,
      "1,234,567.89" => 1_234_567_89,
      "-2,388.00" => -2_388_00,
      "  199.00 " => 199_00
    }.each do |input, paise|
      it "parses #{input.inspect} as #{paise} paise" do
        expect(described_class.parse(input)).to eq(paise)
      end
    end

    [ "", " ", "abc", "1.234", "1,2,3", "12,3456", "1,23,4567", "₹649", "649 Cr", "1e3", "--5", ".5", "5.", nil ].each do |input|
      it "rejects #{input.inspect}" do
        expect { described_class.parse(input) }.to raise_error(ArgumentError)
      end
    end

    it "never produces a Float" do
      expect(described_class.parse("0.10")).to be_a(Integer)
    end
  end

  describe ".format" do
    {
      0 => "₹0.00",
      5 => "₹0.05",
      199_00 => "₹199.00",
      2_388_00 => "₹2,388.00",
      1_23_456_78 => "₹1,23,456.78",
      12_34_56_789_01 => "₹12,34,56,789.01",
      -649_00 => "-₹649.00"
    }.each do |paise, text|
      it "formats #{paise} as #{text}" do
        expect(described_class.format(paise)).to eq(text)
      end
    end

    it "refuses non-integers" do
      expect { described_class.format(1.5) }.to raise_error(ArgumentError)
    end
  end

  it "round-trips: parse(format(n)) == n for random n" do
    rng = Random.new(RSpec.configuration.seed)
    500.times do
      n = rng.rand(-10**13..10**13)
      expect(described_class.parse(described_class.format(n, symbol: ""))).to eq(n)
    end
  end
end
