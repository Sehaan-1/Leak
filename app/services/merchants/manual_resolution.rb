module Merchants
  # The household's own answer for a row in the review queue:
  #
  #   outcome = Merchants::ManualResolution.new(household: household)
  #     .call(txn, counterparty: "merchant", merchant: youtube)
  #   outcome.learned        # => #<MerchantAlias kind: "vpa", pattern: "youtube.premium@okaxis"> or nil
  #   outcome.also_resolved  # => 9 (other rows in review the new alias resolved)
  #
  # Choosing a merchant teaches the rules: the row's UPI ID (or, without
  # one, its payee name) becomes a household MerchantAlias, which beats the
  # catalogue. The other rows in review are resolved again with it, and
  # detection re-runs so findings include them straight away. A person,
  # bank or cash answer only settles that row.
  class ManualResolution
    Outcome = Data.define(:learned, :also_resolved)

    MIN_NAME_LENGTH = 3

    def initialize(household:)
      @household = household
    end

    def call(txn, counterparty:, merchant: nil)
      outcome = ApplicationRecord.transaction do
        txn.update!(merchant: merchant, counterparty: counterparty, resolution: "manual",
          resolution_evidence: "chosen in the review queue", resolution_model: nil, resolved_at: Time.current)
        learned = merchant && learn(txn, merchant)
        Outcome.new(learned, learned ? resolve_others(txn) : 0)
      end
      Detection::Run.new(household: @household).call if merchant
      outcome
    end

    private
      def learn(txn, merchant)
        parsed = Narration.parse(txn.narration)
        name = parsed.payee_key if parsed.payee_key.length >= MIN_NAME_LENGTH
        kind, pattern = [ [ "vpa", MerchantAlias.normalise("vpa", parsed.vpa) ], [ "name", name ] ]
          .find { |_, candidate| candidate.present? }
        return unless pattern

        MerchantAlias.find_or_initialize_by(household: @household, kind: kind, pattern: pattern).tap do |record|
          record.update!(merchant: merchant)
        end
      end

      def resolve_others(txn)
        resolver = Resolver.new(household: @household)
        @household.bank_transactions.needs_review.where.not(id: txn.id).find_each.count do |other|
          result = resolver.resolve(other.narration, amount_paise: other.amount_paise)
          next false if result.abstained?

          other.apply_resolution(result)
          other.save!
        end
      end
  end
end
