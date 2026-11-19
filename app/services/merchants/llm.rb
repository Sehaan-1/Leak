module Merchants
  # Picks the LLM the merchant resolver talks to (config/llm.yml):
  #
  #   client = Merchants::Llm.client  # => HttpClient, CliClient or NullClient
  #   client.complete(messages: [...], schema: {...})  # => JSON string
  #
  # Every client answers `complete(messages:, schema:)` with the model's
  # reply as a string, `#model` (recorded with each verdict) and
  # `#enabled?`. Nothing here logs prompts or replies: they carry
  # narrations, which may come from a real statement.
  module Llm
    class Error < StandardError; end
    class ConfigurationError < Error; end

    CONFIG = Rails.root.join("config/llm.yml")

    module_function

    def config
      @config ||= YAML.safe_load_file(CONFIG).freeze
    end

    def settings = config.fetch("resolver")

    # False, with a warning, when the configuration is broken: a bad LLM
    # setup must never stop an import.
    def enabled?(env: ENV)
      client(env: env).enabled?
    rescue ConfigurationError => error
      Rails.logger.warn("[llm] disabled: #{error.message}")
      false
    end

    def client(env: ENV)
      name = setting(env, "LLM_PROVIDER", :provider)
      name ||= "custom" if setting(env, "LLM_BASE_URL", :base_url)
      name ||= auto_detect(env) unless Rails.env.test?
      return NullClient.new if name.nil? || name == "none"

      build(name, env)
    end

    def build(name, env)
      provider = config.fetch("providers").fetch(name) do
        raise ConfigurationError, "Unknown LLM provider #{name.inspect}; use one of " \
          "#{config.fetch("providers").keys.join(", ")} or none (config/llm.yml)"
      end
      model = setting(env, "LLM_MODEL", :model) || provider["model"]

      case provider.fetch("kind")
      when "cli"
        CliClient.new(command: provider.fetch("command"), model: model, timeout: settings.fetch("timeout_seconds"))
      else
        base_url = setting(env, "LLM_BASE_URL", :base_url) || provider["base_url"]
        raise ConfigurationError, "LLM provider #{name} needs LLM_BASE_URL" if base_url.blank?
        raise ConfigurationError, "LLM provider #{name} needs LLM_MODEL" if model.blank?

        api_key = setting(env, "LLM_API_KEY", :api_key) || provider["api_key_env"]&.then { |var| env[var].presence }
        if provider["api_key_env"] && api_key.blank?
          raise ConfigurationError, "LLM provider #{name} needs #{provider["api_key_env"]} (or LLM_API_KEY)"
        end

        HttpClient.new(base_url: base_url, api_key: api_key, model: model, provider: name,
          response_format: setting(env, "LLM_RESPONSE_FORMAT", :response_format) || provider.fetch("response_format"),
          timeout: settings.fetch("timeout_seconds"), max_attempts: settings.fetch("max_attempts"))
      end
    end

    # The user's order: an installed coding agent, then a free API key.
    def auto_detect(env)
      config.fetch("auto_order").find do |name|
        provider = config.fetch("providers").fetch(name)
        if provider["kind"] == "cli" then CliClient.installed?(provider.fetch("command"), env)
        elsif name == "custom" then false # chosen above when LLM_BASE_URL is set
        else env[provider.fetch("api_key_env")].present?
        end
      end
    end

    def setting(env, var, credential)
      env[var].presence || Rails.application.credentials.dig(:llm, credential).presence
    end

    # A model's reply as a Hash: tolerates ```json fences and chatter around
    # the object (agents and json_object-mode models add both).
    def parse_json(text)
      body = text.to_s.gsub(/\e\[[0-9;]*m/, "")
      start = body.index("{")
      stop = body.rindex("}")
      raise Error, "the model's reply has no JSON object" unless start && stop && stop > start

      JSON.parse(body[start..stop])
    rescue JSON::ParserError
      raise Error, "the model's reply isn't valid JSON"
    end
  end
end
