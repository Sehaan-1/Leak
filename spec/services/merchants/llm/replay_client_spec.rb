require "rails_helper"

RSpec.describe Merchants::Llm::ReplayClient do
  let(:path) { Rails.root.join("tmp/spec-replay-#{SecureRandom.hex(4)}.json") }
  let(:messages) { [ { role: "user", content: "Rows:\n{\"id\":\"r1\"}" } ] }
  let(:schema) { { type: "object" } }

  after { FileUtils.rm_f(path) }

  it "records live replies, then replays them offline" do
    live = FakeLlm.new { |row| { "id" => row["id"], "label" => "unknown", "confidence" => 1, "evidence" => "" } }
    recorder = described_class.new(path, record: live)
    reply = recorder.complete(messages: messages, schema: schema)
    recorder.save!(prompt_version: "merchant-v1")

    saved = JSON.parse(path.read)
    expect(saved).to include("provider" => "fake", "model" => "fake-model", "prompt_version" => "merchant-v1")
    expect(saved["replies"].values).to eq([ reply ])

    replay = described_class.new(path)
    expect(replay).to have_attributes(model: "fake-model", name: "replay", recording?: false)
    expect(replay.complete(messages: messages, schema: schema)).to eq(reply)
  end

  it "fails on a request it hasn't recorded (the prompt or rows changed)" do
    expect { described_class.new(path).complete(messages: messages, schema: schema) }
      .to raise_error(described_class::Miss, /no recorded reply/)
  end
end
