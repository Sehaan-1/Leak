require "net/http"

module Merchants
  module Llm
    # Any OpenAI-compatible chat completions endpoint: Gemini, NVIDIA NIM,
    # OpenAI, OpenRouter, Groq, ollama, or your own.
    #
    #   HttpClient.new(base_url: "https://integrate.api.nvidia.com/v1", api_key: "nvapi-...",
    #     model: "meta/llama-3.3-70b-instruct", response_format: "json_object")
    #
    # Retries rate limits (429) and server errors with backoff, honouring
    # Retry-After. Error messages never include the request, and only the
    # provider's own error message from the response.
    class HttpClient
      RETRY = [ 408, 429, 500, 502, 503, 504 ].freeze
      FORMATS = %w[ json_schema json_object none ].freeze

      attr_reader :model, :name

      # transport: ->(uri, headers, body, timeout) { [status, headers, body] }, for specs.
      def initialize(base_url:, api_key:, model:, response_format: "json_schema", provider: "custom", timeout: 90,
                     max_attempts: 4, transport: nil, sleeper: ->(seconds) { sleep(seconds) })
        raise ConfigurationError, "LLM_RESPONSE_FORMAT must be one of #{FORMATS.join(", ")}" unless FORMATS.include?(response_format)

        @uri = URI.join(base_url.to_s.chomp("/") + "/", "chat/completions")
        @api_key = api_key
        @model = model
        @name = provider
        @response_format = response_format
        @timeout = timeout
        @max_attempts = max_attempts
        @transport = transport || method(:post)
        @sleeper = sleeper
      end

      def enabled? = true

      def complete(messages:, schema:)
        body = JSON.generate(request_body(messages, schema))
        headers = { "Content-Type" => "application/json", "Accept" => "application/json" }
        headers["Authorization"] = "Bearer #{@api_key}" if @api_key.present?

        attempt = 0
        loop do
          attempt += 1
          status, response_headers, response_body = @transport.call(@uri, headers, body, @timeout)
          return content(response_body) if status.between?(200, 299)

          if RETRY.include?(status) && attempt < @max_attempts
            @sleeper.call(backoff(response_headers, attempt))
            next
          end
          raise Error, "#{@name} returned HTTP #{status}#{provider_message(response_body)}"
        end
      rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => error
        raise Error, "#{@name} could not be reached (#{error.class})"
      end

      private
        def request_body(messages, schema)
          body = { model: @model, messages: messages, temperature: 0 }
          case @response_format
          when "json_schema"
            body[:response_format] = { type: "json_schema", json_schema: { name: "merchant_answers", strict: true, schema: schema } }
          when "json_object"
            body[:response_format] = { type: "json_object" }
          end
          body
        end

        def content(response_body)
          JSON.parse(response_body.to_s).dig("choices", 0, "message", "content").presence ||
            raise(Error, "#{@name} returned no message content")
        rescue JSON::ParserError
          raise Error, "#{@name} returned a response that isn't JSON (#{response_body.to_s.bytesize} bytes)"
        end

        def backoff(headers, attempt)
          retry_after = headers.to_h.transform_keys(&:downcase)["retry-after"]
          seconds = Array(retry_after).first.to_s
          seconds.match?(/\A\d+(\.\d+)?\z/) ? [ seconds.to_f, 60 ].min : 2**attempt
        end

        def provider_message(response_body)
          message = JSON.parse(response_body.to_s).then { |json| json.is_a?(Array) ? json.first : json }
            .then { |json| json.is_a?(Hash) ? json.dig("error", "message") || json["message"] || json["detail"] : nil }
          message.is_a?(String) ? ": #{message.first(200)}" : ""
        rescue JSON::ParserError
          ""
        end

        def post(uri, headers, body, timeout)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = 10
          http.read_timeout = timeout
          request = Net::HTTP::Post.new(uri, headers)
          request.body = body
          response = http.request(request)
          [ response.code.to_i, response.each_header.to_h, response.body ]
        end
    end
  end
end
