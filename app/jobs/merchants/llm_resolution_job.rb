module Merchants
  # Sends a household's rows still in review to the LLM resolver after an
  # import. Provider errors (rate limits, outages) retry with backoff; rows
  # stay in review meanwhile.
  class LlmResolutionJob < ApplicationJob
    queue_as :default

    retry_on Merchants::Llm::Error, wait: :polynomially_longer, attempts: 5
    discard_on ActiveRecord::RecordNotFound, Merchants::Llm::ConfigurationError

    def self.enqueue_for(household)
      perform_later(household.id) if Merchants::Llm.enabled?
    end

    def perform(household_id)
      household = Household.find(household_id)
      resolved = LlmResolver.new(household: household).resolve_pending!(household.bank_transactions)
      Rails.logger.info("[llm] resolved #{resolved} rows for household #{household_id}")
    end
  end
end
