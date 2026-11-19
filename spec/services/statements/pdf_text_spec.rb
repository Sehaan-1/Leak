require "rails_helper"

RSpec.describe Statements::PdfText do
  it "extracts the layout text of the sample PDF" do
    require_pdftotext!
    text = described_class.extract(StatementFixtures::SAMPLE_PDF)
    expect(text).to eq(sample_text)
  end

  it "rejects files that aren't PDFs" do
    Tempfile.create([ "statement", ".pdf" ]) do |file|
      file.write("Date,Narration,Amount\n")
      file.flush
      expect { described_class.extract(file.path) }.to raise_error(Statements::ExtractionFailed, /isn't a PDF/)
    end
  end

  it "asks for the password when pdftotext reports one is needed" do
    failed = instance_double(Process::Status, success?: false)
    allow(described_class).to receive(:run).and_return([ "", "Command Line Error: Incorrect password\n", failed ])
    expect { described_class.extract(StatementFixtures::SAMPLE_PDF, password: "wrong") }
      .to raise_error(Statements::PasswordRequired)
    expect(described_class).to have_received(:run).with(array_including("-upw", "wrong"))
  end

  it "rejects scanned PDFs with no text layer" do
    allow(described_class).to receive(:run).and_return([ "  \n\f", "", instance_double(Process::Status, success?: true) ])
    expect { described_class.extract(StatementFixtures::SAMPLE_PDF) }.to raise_error(Statements::NoTextLayer)
  end
end
