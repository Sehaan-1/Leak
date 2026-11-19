require "rails_helper"

RSpec.describe Merchants::Llm do
  describe ".client" do
    it "is off in tests unless a provider is named" do
      expect(described_class.client(env: { "GEMINI_API_KEY" => "k" })).to be_a(Merchants::Llm::NullClient)
      expect(described_class.enabled?(env: {})).to be(false)
      expect(described_class.client(env: { "LLM_PROVIDER" => "none" })).not_to be_enabled
    end

    it "builds a named provider from its preset, with overrides" do
      client = described_class.client(env: { "LLM_PROVIDER" => "gemini", "GEMINI_API_KEY" => "k" })
      expect(client).to have_attributes(class: Merchants::Llm::HttpClient, name: "gemini", model: described_class.config.dig("providers", "gemini", "model"))

      nvidia = described_class.client(env: { "LLM_PROVIDER" => "nvidia", "LLM_API_KEY" => "nvapi-x", "LLM_MODEL" => "openai/gpt-oss-120b" })
      expect(nvidia).to have_attributes(name: "nvidia", model: "openai/gpt-oss-120b")
    end

    it "treats LLM_BASE_URL alone as a custom OpenAI-compatible endpoint" do
      client = described_class.client(env: { "LLM_BASE_URL" => "http://gpu-box:8000/v1", "LLM_MODEL" => "qwen3" })
      expect(client).to have_attributes(name: "custom", model: "qwen3")
    end

    it "explains a broken setup, and never lets it stop an import" do
      expect { described_class.client(env: { "LLM_PROVIDER" => "nvidia" }) }
        .to raise_error(Merchants::Llm::ConfigurationError, /NVIDIA_API_KEY/)
      expect { described_class.client(env: { "LLM_PROVIDER" => "claude-web" }) }
        .to raise_error(Merchants::Llm::ConfigurationError, /Unknown LLM provider/)
      expect(described_class.enabled?(env: { "LLM_PROVIDER" => "nvidia" })).to be(false)
    end

    it "uses an installed agent CLI" do
      expect(described_class.client(env: { "LLM_PROVIDER" => "agy" })).to have_attributes(class: Merchants::Llm::CliClient, name: "agy")
    end
  end

  describe ".auto_detect" do
    around do |example|
      Dir.mktmpdir do |dir|
        @bin = dir
        example.run
      end
    end

    def install(command)
      path = File.join(@bin, command)
      File.write(path, "#!/bin/sh\n")
      File.chmod(0o755, path)
    end

    it "prefers an installed agent, then a Gemini key, then an NVIDIA key" do
      expect(described_class.auto_detect({ "PATH" => @bin })).to be_nil
      expect(described_class.auto_detect({ "PATH" => @bin, "NVIDIA_API_KEY" => "n" })).to eq("nvidia")
      expect(described_class.auto_detect({ "PATH" => @bin, "NVIDIA_API_KEY" => "n", "GEMINI_API_KEY" => "g" })).to eq("gemini")
      install("opencode")
      expect(described_class.auto_detect({ "PATH" => @bin, "GEMINI_API_KEY" => "g" })).to eq("opencode")
      install("agy")
      expect(described_class.auto_detect({ "PATH" => @bin })).to eq("agy")
    end
  end

  describe ".parse_json" do
    it "reads an object out of fences and chatter" do
      expect(described_class.parse_json("Sure!\n```json\n{\"answers\": []}\n```")).to eq("answers" => [])
      expect { described_class.parse_json("no idea") }.to raise_error(Merchants::Llm::Error, /no JSON object/)
      expect { described_class.parse_json("{nope}") }.to raise_error(Merchants::Llm::Error, /isn't valid JSON/)
    end
  end
end
