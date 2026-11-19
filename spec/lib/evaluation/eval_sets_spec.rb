require "rails_helper"

# The labelled sets behind `bin/rails leak:eval:merchants`. The golden set is
# frozen; the gate itself runs as its own CI step.
RSpec.describe "merchant resolution eval sets" do
  let(:config) { Evaluation::Gate.config }
  let(:golden) { Evaluation::MerchantResolution.load(Rails.root.join(config["golden"])) }
  let(:dev) { Evaluation::MerchantResolution.load(Rails.root.join(config["dev"])) }
  let(:labels) { Merchants::Catalogue.entries.map(&:slug) + %w[ unknown person bank cash ] }

  it "keeps the golden set frozen" do
    expect(Digest::SHA256.file(Rails.root.join(config["golden"])).hexdigest).to eq(config["golden_sha256"])
  end

  it "has 300 golden rows and a separate, larger dev set" do
    expect(golden.size).to eq(300)
    expect(dev.size).to be >= 500
    expect(golden.map { _1[:id] }).to all(be_present)
    expect((golden + dev).map { _1[:id] }.uniq.size).to eq(golden.size + dev.size)
    # Bank and cash entries are fixed strings ("CREDIT INTEREST"); everything else carries random references.
    varied = ->(rows) { rows.reject { %w[ bank cash ].include?(_1[:label]) }.map { _1[:narration] } }
    expect(varied.(golden) & varied.(dev)).to eq([])
  end

  it "uses only known labels and real-looking rows" do
    (golden + dev).each do |row|
      expect(labels).to include(row[:label]), "#{row[:id]} has unknown label #{row[:label]}"
      expect(row[:amount_paise]).to be_an(Integer).and(satisfy(&:nonzero?))
      expect(row[:narration]).to be_present
    end
  end

  it "runs the gate on the golden set" do
    out = StringIO.new
    status = Evaluation::Gate.run(set: "golden", out: out)
    expect(out.string).to include("Merchant accuracy")
    expect(status).to eq(0), out.string
  end
end
