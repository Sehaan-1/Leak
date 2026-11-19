module Merchants
  module Llm
    # No LLM configured: the LLM step is skipped and abstentions go
    # straight to review.
    class NullClient
      def enabled? = false
      def model = nil
      def name = "none"

      def complete(messages:, schema:)
        raise Error, "no LLM provider is configured (config/llm.yml)"
      end
    end
  end
end
