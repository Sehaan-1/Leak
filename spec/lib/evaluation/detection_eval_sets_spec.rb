require "rails_helper"

# The labelled histories behind `bin/rails leak:eval:detection`. The golden
# set is frozen; the gate itself runs as its own CI step.
RSpec.describe "detection eval sets" do
  let(:config) { Evaluation::DetectionGate.config }
  let(:golden) { Evaluation::RecurringDetection.load(Rails.root.join(config["golden"])) }
  let(:dev) { Evaluation::RecurringDetection.load(Rails.root.join(config["dev"])) }

  it "keeps the golden set frozen" do
    expect(Digest::SHA256.file(Rails.root.join(config["golden"])).hexdigest).to eq(config["golden_sha256"])
  end

  it "has 100 golden histories and a separate dev set" do
    expect(golden.size).to eq(100)
    expect(dev.size).to be >= 50
    expect((golden + dev).map { _1["id"] }.uniq.size).to eq(golden.size + dev.size)
  end

  it "runs the gate on the golden set" do
    out = StringIO.new
    status = Evaluation::DetectionGate.run(set: "golden", out: out)
    expect(out.string).to include("per 100 charges")
    expect(status).to eq(0), out.string
  end
end
