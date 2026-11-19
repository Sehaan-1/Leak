require "rails_helper"

RSpec.describe Statements::Parsers::Sbi do
  describe "the fabricated SBI sample (real pdftotext -layout output)" do
    subject(:statement) { described_class.parse(sample_text) }

    it "is recognised as SBI" do
      expect(described_class.matches?(sample_text)).to be(true)
    end

    it "reads the header" do
      expect(statement).to have_attributes(
        bank: "sbi", account_number: "39481029475", account_last4: "9475", ifsc: "SBIN0009482",
        period_from: Date.new(2026, 11, 1), period_to: Date.new(2026, 11, 19),
        statement_date: Date.new(2026, 11, 19), closing_balance_paise: 24_850_75
      )
    end

    it "reads all seven rows across both pages, with amounts and balances" do
      expect(statement.rows.map { |r| [ r.posted_on.day, r.debit_paise, r.credit_paise, r.balance_paise ] }).to eq([
        [ 1, 0, 15_000_00, 27_450_25 ],
        [ 1, 1_245_50, 0, 26_204_75 ],
        [ 2, 680_00, 0, 25_524_75 ],
        [ 4, 199_00, 0, 25_325_75 ],
        [ 5, 0, 4_200_00, 29_525_75 ],
        [ 10, 2_850_00, 0, 26_675_75 ],
        [ 15, 1_825_00, 0, 24_850_75 ]
      ])
    end

    it "joins wrapped narrations and keeps footers out of them" do
      expect(statement.rows[3].narration).to eq(
        "WDL TFR UPI/DR/630843833086/CLOUD STORAGE/YESB/cloudpay@yesbank/Mand ate 0097692162094 AT 09482 BIDHANNAGAR"
      )
      expect(statement.rows[5].narration).to start_with("WDL TFR UPI/DR/631490281745/CITY POWER CORP/SBIN/citypower@sbi")
      expect(statement.rows.map(&:narration).join).not_to match(/Page|Sample|fictitious/i)
    end

    it "treats '-' in the reference column as no reference" do
      expect(statement.rows.map(&:ref)).to all(be_nil)
    end

    it "records the text line each row starts on" do
      lines = sample_text.delete("\f").split("\n")
      statement.rows.each { |row| expect(lines[row.line_no - 1]).to include(row.posted_on.strftime("%d/%m/%Y")) }
    end
  end

  describe "malformed input" do
    it "rejects a dated line it cannot read, naming the line" do
      text = sample_text.sub("05/11/2026 05/11/2026", "05/11/2026 31/02/2026")
      expect { described_class.parse(text) }.to raise_error(Statements::ParseError, /Line \d+: "31\/02\/2026" is not a valid date/)
    end

    it "rejects a row with both a debit and a credit" do
      text = sample_text.sub(/-(\s+)15,000\.00/) { "9.00#{$1.delete_prefix("   ")}15,000.00" }
      expect { described_class.parse(text) }.to raise_error(Statements::ParseError, /exactly one of debit or credit/)
    end

    it "rejects a statement without transactions" do
      header_only = sample_text.lines.take_while { |l| !l.include?("01/11/2026") }.join
      expect { described_class.parse(header_only) }.to raise_error(Statements::ParseError, /No transactions/)
    end
  end

  # Property: whatever the synthetic generator renders (wrapping, page
  # breaks, twin charges, debit-balance months), the parser recovers exactly.
  describe "round-trip property on synthetic statements" do
    it "parses back every rendered transaction" do
      rng = Random.new(RSpec.configuration.seed)
      25.times do
        from = Date.new(2026, rng.rand(1..10), rng.rand(1..28))
        history = SyntheticSbi.history(rng, from: from, to: from + rng.rand(3..40), per_day: 0..3)
        next if history.empty?

        opening = rng.rand(-5_000_00..80_000_00)
        text = SyntheticSbi.render(rows: history, opening_paise: opening, from: from, to: history.last.posted_on)
        rows = described_class.parse(text).rows

        expect(rows.size).to eq(history.size)
        rows.zip(history).each do |row, txn|
          expect(row.posted_on).to eq(txn.posted_on)
          expect(row.amount_paise).to eq(txn.amount_paise)
          expect(row.narration.delete(" ")).to eq(txn.narration.delete(" "))
        end
        expect(rows.last.balance_paise).to eq(opening + history.sum(&:amount_paise))
      end
    end
  end
end
