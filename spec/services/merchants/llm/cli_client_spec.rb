require "rails_helper"

RSpec.describe Merchants::Llm::CliClient do
  let(:runs) { [] }
  let(:output) { [ "", "", true ] }
  let(:runner) do
    lambda do |argv, timeout|
      runs << { argv: argv, timeout: timeout }
      output
    end
  end
  let(:messages) { [ { role: "system", content: "You identify..." }, { role: "user", content: "Rows:\n{}" } ] }
  let(:schema) { { type: "object", required: [ "answers" ] } }

  it "runs Antigravity headless with the schema and reads its structured output" do
    output[0] = JSON.generate(status: "SUCCESS", response: "ignored", structured_output: { answers: [] })
    reply = described_class.new(command: "agy", model: "gemini-3-flash", timeout: 60, runner: runner).complete(messages: messages, schema: schema)

    expect(reply).to eq("{\"answers\":[]}")
    argv = runs.sole[:argv]
    expect(argv.first(2)).to eq(%w[ agy -p ])
    expect(argv[2]).to include("You identify...", "Rows:", "It must match this JSON schema")
    expect(argv.each_cons(2).to_a).to include([ "--output-format", "json" ], [ "--json-schema", JSON.generate(schema) ],
      [ "--print-timeout", "60s" ], [ "--model", "gemini-3-flash" ])
  end

  it "falls back to agy's text response and rejects a failed run" do
    output[0] = JSON.generate(status: "SUCCESS", response: "```json\n{\"answers\":[]}\n```")
    expect(described_class.new(command: "agy", runner: runner).complete(messages: messages, schema: schema)).to include("{\"answers\":[]}")

    output[0] = JSON.generate(status: "ERROR")
    expect { described_class.new(command: "agy", runner: runner).complete(messages: messages, schema: schema) }
      .to raise_error(Merchants::Llm::Error, /status "ERROR"/)
    output[2] = false
    expect { described_class.new(command: "agy", runner: runner).complete(messages: messages, schema: schema) }
      .to raise_error(Merchants::Llm::Error, /logged in/)
  end

  it "runs opencode with the prompt and returns what it printed" do
    output[0] = "Here you go:\n{\"answers\": []}\n"
    reply = described_class.new(command: "opencode", model: "anthropic/claude-sonnet-4", runner: runner).complete(messages: messages, schema: schema)
    expect(reply).to include("{\"answers\": []}")
    expect(runs.sole[:argv].first(4)).to eq(%w[ opencode run -m anthropic/claude-sonnet-4 ])
  end

  it "runs only the agents it knows" do
    expect { described_class.new(command: "rm") }.to raise_error(Merchants::Llm::ConfigurationError)
  end

  it "really runs a command, in an empty directory, and enforces the timeout" do
    client = described_class.new(command: "opencode", timeout: 1)
    expect(client.send(:run, [ "sh", "-c", "pwd; ls | wc -l" ], 5)).to match([ a_string_matching(%r{leak-llm.*\n\s*0\n}m), "", true ])
    expect { client.send(:run, [ "sleep", "10" ], 0) }.to raise_error(Merchants::Llm::Error, /timed out/)
    expect { client.send(:run, [ "no-such-agent-here" ], 5) }.to raise_error(Merchants::Llm::Error, /isn't installed/)
  end
end
