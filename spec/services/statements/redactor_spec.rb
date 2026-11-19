require "rails_helper"

RSpec.describe Statements::Redactor do
  it "keeps the layout but removes names, numbers and handles" do
    redacted = described_class.redact(sample_text)

    expect(redacted.lines.map(&:length)).to eq(sample_text.lines.map(&:length))
    expect(redacted).not_to match(/AARAV|SHARMA|ANANYA|39481029475|okaxis|15,000\.00/)
    expect(redacted).to include("Post Date Details", "Debit", "Credit", "Balance", "99/99/9999", "99,999.99")
  end

  it "masks the IFSC code too, so redacted text is never mistaken for a real statement" do
    expect(Statements::Parsers::Sbi.matches?(described_class.redact(sample_text))).to be(false) # IFSC is masked
    expect(described_class.redact(sample_text)).to match(/IFSC Code\s+: XXXX9999999/)
  end
end
