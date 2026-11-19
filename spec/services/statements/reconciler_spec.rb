require "rails_helper"

RSpec.describe Statements::Reconciler do
  let(:statement) { Statements::Parsers::Sbi.parse(sample_text) }

  it "accepts the sample and derives its opening balance" do
    expect(described_class.check!(statement)).to eq(12_450_25)
  end

  it "names the exact row that doesn't tie" do
    tampered = sample_text.sub("25,524.75", "25,542.75") # transposed digits on row 3
    expect { described_class.check!(Statements::Parsers::Sbi.parse(tampered)) }
      .to raise_error(Statements::DoesNotTie, /Row 3 \(02\/11\/2026 WDL TFR UPI.*\) doesn't tie: the balance should be ₹25,524.75 but the statement shows ₹25,542.75 \(off by ₹18.00\)/)
  end

  it "catches a missing row through the running balance" do
    lines = sample_text.lines
    start = lines.index { |l| l.include?("02/11/2026 02/11/2026") }
    tampered = (lines[0...start] + lines[(start + 3)..]).join # drop row 3 and its two continuation lines
    expect { described_class.check!(Statements::Parsers::Sbi.parse(tampered)) }
      .to raise_error(Statements::DoesNotTie, /Row 3 .* doesn't tie/)
  end

  it "catches a missing last row through the header's closing balance" do
    lines = sample_text.lines
    start = lines.index { |l| l.include?("15/11/2026 15/11/2026") }
    tampered = (lines[0...start] + lines[(start + 4)..]).join
    expect { described_class.check!(Statements::Parsers::Sbi.parse(tampered)) }
      .to raise_error(Statements::DoesNotTie, /closing balance \(₹24,850.75\)/)
  end

  it "rejects rows outside the statement period" do
    tampered = sample_text.sub("Statement From : 01-11-2026", "Statement From : 02-11-2026")
    expect { described_class.check!(Statements::Parsers::Sbi.parse(tampered)) }
      .to raise_error(Statements::DoesNotTie, /Row 1 .* outside the statement period/)
  end

  it "rejects rows out of date order" do
    tampered = sample_text.sub("04/11/2026 04/11/2026", "01/11/2026 01/11/2026")
    tampered = tampered.sub("05/11/2026 05/11/2026", "03/11/2026 03/11/2026").sub("02/11/2026 02/11/2026", "03/11/2026 03/11/2026")
    expect { described_class.check!(Statements::Parsers::Sbi.parse(tampered)) }
      .to raise_error(Statements::DoesNotTie, /dated before the row above it/)
  end
end
