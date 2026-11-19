module Api
  module V1
    # Rows nobody could resolve to a counterparty (the rules and, if
    # configured, the LLM abstained), newest first, with the payee and UPI
    # ID read from the narration and why it was left for review.
    class ReviewItemsController < BaseController
      LIMIT = 200

      def index
        scope = current_household.bank_transactions.needs_review
        rows = scope.includes(bank_account: :account).order(posted_on: :desc, id: :desc).limit(LIMIT)
        render json: { review_items: rows.map { |row| self.class.payload(row) }, total_count: scope.count }
      end

      # The parser compares payees space-free ("GOOGLEPLAY"); show the
      # narration's own spelling of it ("GOOGLE PLAY") when it can be found.
      def self.display_payee(narration, payee)
        return if payee.blank?

        narration.split("/").map(&:squish).find { |part| Merchants::Text.compact(part) == payee } || payee
      end

      def self.payload(row)
        parsed = Merchants::Narration.parse(row.narration)
        {
          id: row.id,
          posted_on: row.posted_on.iso8601,
          narration: row.narration,
          amount_paise: row.amount_paise,
          payee: display_payee(row.narration, parsed.payee),
          upi_id: parsed.vpa,
          reason: row.resolution_evidence,
          bank_account: { id: row.bank_account.id, name: row.bank_account.display_name }
        }
      end
    end
  end
end
