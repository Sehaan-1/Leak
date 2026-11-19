require "rails_helper"

RSpec.describe Evaluation::Gate do
  let(:out) { StringIO.new }
  let(:path) { Rails.root.join("tmp/spec-replay-#{SecureRandom.hex(4)}.json") }

  before do
    allow(described_class).to receive(:replay_path).and_return(path)
    # Keep these runs out of the CI job summary.
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("GITHUB_STEP_SUMMARY").and_return(nil)
  end
  after { FileUtils.rm_f(path) }

  it "skips the LLM gate, with a notice, until replies are recorded" do
    expect(described_class.run(set: "dev", llm: "replay", out: out)).to eq(0)
    expect(out.string).to include("Merchant resolution, rules only, dev set", "no recorded LLM replies for dev yet")
  end

  it "fails when the recording is stale" do
    path.write(JSON.generate("model" => "m", "replies" => {}))
    expect(described_class.run(set: "dev", llm: "replay", out: out)).to eq(1)
    expect(out.string).to include("the LLM replay for dev is stale", "LLM_EVAL=record")
  end

  it "scores rules + LLM from a recording" do
    live = FakeLlm.new { |row| { "id" => row["id"], "label" => "unknown", "confidence" => 0.9, "evidence" => "" } }
    allow(Merchants::Llm).to receive(:client).and_return(live)

    expect(described_class.run(set: "dev", llm: "record", out: out)).to eq(0)
    expect(path).to exist
    expect(live.requests).not_to be_empty

    replayed = StringIO.new
    expect(described_class.run(set: "dev", llm: "replay", out: replayed)).to eq(0)
    expect(replayed.string).to include("rules + LLM (fake-model, replay)", "vs rules only: 0 more answered")
  end

  it "refuses an unknown mode" do
    expect { described_class.run(set: "dev", llm: "yolo", out: out) }.to raise_error(ArgumentError, /LLM_EVAL/)
  end
end
