module Merchants
  # Rules first, then the LLM for what the rules abstained on, then the
  # validators:
  #
  #   resolver = Merchants::LlmResolver.new(household: household)  # client: Llm.client
  #   resolver.resolve_many([ narration, ... ])  # => [Resolver::Result, ...] (via "llm" when the LLM decided)
  #   resolver.resolve_pending!(household.bank_transactions)       # saves verdicts for rows still in review
  #
  # The LLM only maps a narration to a catalogue merchant or "person"; it
  # never sees amounts or dates, and rows it can't place stay in review with
  # its reason as evidence. Prompts and replies are never logged.
  class LlmResolver
    attr_reader :client, :rules

    def initialize(household: nil, client: Llm.client, settings: Llm.settings, rules: Resolver.new(household: household))
      @household = household
      @client = client
      @settings = settings
      @rules = rules
    end

    def enabled? = client.enabled?

    def resolve_many(narrations)
      results = narrations.map { |narration| rules.resolve(narration) }
      pending = results.each_index.select { |index| results[index].abstained? }
      verdicts = consult(pending.map { |index| narrations[index] })
      pending.zip(verdicts).each { |index, result| results[index] = result if result }
      results
    end

    # Rows in review the LLM hasn't seen yet. Rows it has answered are
    # stamped llm_checked_at whatever the verdict, so they aren't sent again;
    # if the provider fails, nothing is stamped and the error propagates
    # (the job retries).
    def resolve_pending!(scope)
      return 0 unless enabled?

      count = 0
      scope.needs_review.where(llm_checked_at: nil).find_in_batches(batch_size: @settings.fetch("batch_size")) do |batch|
        verdicts = consult(batch.map(&:narration))
        BankTransaction.transaction do
          batch.zip(verdicts).each do |txn, result|
            txn.apply_resolution(result) if result
            txn.llm_checked_at = Time.current
            txn.save!
            count += 1 unless result.nil? || result.abstained?
          end
        end
      end
      count
    end

    private
      # One result per narration: an LLM verdict, an abstention with the
      # validator's reason, or nil when the LLM isn't available.
      def consult(narrations)
        return Array.new(narrations.size) if narrations.empty? || !enabled?

        prompt = Llm::Prompt.new(catalogue: catalogue)
        validator = Llm::Validator.new(catalogue: catalogue, min_confidence: @settings.fetch("min_confidence"),
          min_similarity: @settings.fetch("min_evidence_similarity"))

        narrations.each_slice(@settings.fetch("batch_size")).flat_map do |slice|
          rows = slice.each_with_index.map { |narration, index| { id: "r#{index + 1}", parsed: Narration.parse(narration) } }
          reply = Llm.parse_json(client.complete(messages: prompt.messages(rows), schema: prompt.schema))
          answers = Array(reply["answers"]).select { |answer| answer.is_a?(Hash) }.group_by { |answer| answer["id"].to_s }

          rows.map do |row|
            # An id answered twice is ambiguous: treat it as unanswered.
            given = answers.fetch(row[:id], [])
            result(validator.check(given.one? ? given.first : nil, row[:parsed]))
          end
        end
      end

      def result(verdict)
        return Resolver::Result.new(nil, nil, "abstained", verdict.evidence, client.model) unless verdict.accepted?
        if verdict.label == Llm::Prompt::PERSON
          return Resolver::Result.new(nil, "person", "llm", verdict.evidence, client.model)
        end

        Resolver::Result.new(merchants.fetch(verdict.label), "merchant", "llm", verdict.evidence, client.model)
      end

      def catalogue = @catalogue ||= Llm::Prompt.catalogue_for(@household)
      def merchants = @merchants ||= Merchant.where(slug: catalogue.map(&:slug)).index_by(&:slug)
  end
end
