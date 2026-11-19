require "rails_helper"

RSpec.describe Merchants::Llm::HttpClient do
  let(:calls) { [] }
  let(:replies) { [] }
  let(:sleeps) { [] }
  let(:transport) do
    lambda do |uri, headers, body, timeout|
      calls << { uri: uri, headers: headers, body: JSON.parse(body), timeout: timeout }
      replies.shift
    end
  end
  let(:messages) { [ { role: "user", content: "secret narration" } ] }
  let(:schema) { { type: "object" } }

  def client(**options)
    described_class.new(base_url: "https://integrate.api.nvidia.com/v1/", api_key: "nvapi-x", model: "m", provider: "nvidia",
      transport: transport, sleeper: ->(seconds) { sleeps << seconds }, **options)
  end

  def ok(content) = [ 200, {}, JSON.generate(choices: [ { message: { content: content } } ]) ]

  it "posts an OpenAI-style chat completion with a strict JSON schema" do
    replies << ok("{\"answers\":[]}")
    expect(client.complete(messages: messages, schema: schema)).to eq("{\"answers\":[]}")

    call = calls.sole
    expect(call[:uri].to_s).to eq("https://integrate.api.nvidia.com/v1/chat/completions")
    expect(call[:headers]).to include("Authorization" => "Bearer nvapi-x")
    expect(call[:body]).to include("model" => "m", "temperature" => 0, "messages" => [ { "role" => "user", "content" => "secret narration" } ])
    expect(call[:body]["response_format"]).to eq("type" => "json_schema",
      "json_schema" => { "name" => "merchant_answers", "strict" => true, "schema" => { "type" => "object" } })
  end

  it "asks for a plain JSON object, or nothing, when the provider can't do schemas" do
    replies << ok("{}") << ok("{}")
    client(response_format: "json_object").complete(messages: messages, schema: schema)
    client(response_format: "none").complete(messages: messages, schema: schema)
    expect(calls.map { |call| call[:body]["response_format"] }).to eq([ { "type" => "json_object" }, nil ])
    expect { client(response_format: "xml") }.to raise_error(Merchants::Llm::ConfigurationError)
  end

  it "retries rate limits and outages, honouring Retry-After" do
    replies << [ 429, { "retry-after" => "7" }, "" ] << [ 503, {}, "" ] << ok("{}")
    expect(client.complete(messages: messages, schema: schema)).to eq("{}")
    expect(sleeps).to eq([ 7.0, 4 ])
  end

  it "gives up after max_attempts, with the provider's own error message" do
    replies << [ 401, {}, JSON.generate(error: { message: "Invalid API key" }) ]
    expect { client.complete(messages: messages, schema: schema) }
      .to raise_error(Merchants::Llm::Error, "nvidia returned HTTP 401: Invalid API key")

    replies.concat(Array.new(4) { [ 429, {}, "rate limited" ] })
    expect { client.complete(messages: messages, schema: schema) }.to raise_error(Merchants::Llm::Error, "nvidia returned HTTP 429")
    expect(calls.size).to eq(5)
  end

  it "treats unreachable hosts and empty replies as errors" do
    failing = ->(*) { raise Errno::ECONNREFUSED }
    expect { client(transport: failing).complete(messages: messages, schema: schema) }
      .to raise_error(Merchants::Llm::Error, "nvidia could not be reached (Errno::ECONNREFUSED)")
    replies << [ 200, {}, "{\"choices\":[]}" ]
    expect { client.complete(messages: messages, schema: schema) }.to raise_error(Merchants::Llm::Error, /no message content/)
  end
end
