module Merchants
  module Llm
    # The request sent to the LLM for a batch of narrations the rules
    # abstained on: the catalogue, the rows, and a JSON schema that only
    # admits catalogue slugs, "person" or "unknown".
    #
    #   prompt = Prompt.new(catalogue: Prompt.catalogue_for(household))
    #   prompt.messages(rows)  # rows: [{ id: "r1", parsed: Narration::Parsed }]
    #   prompt.schema
    #
    # Runs of five or more digits (references, account and phone numbers,
    # terminal codes) are masked before anything leaves the app: they don't
    # help name a merchant, and phone numbers identify people.
    class Prompt
      DIGITS = /\d{5,}/
      PERSON = "person"
      UNKNOWN = "unknown"

      Entry = Data.define(:slug, :name, :names, :vpas)

      def self.mask(text) = text.to_s.gsub(DIGITS, "#")

      # Catalogue merchants plus a household's own aliases, sorted so the
      # prompt (and its replay key) is stable.
      def self.catalogue_for(household)
        aliases = MerchantAlias.for_household(household).pluck(:merchant_id, :kind, :pattern).group_by(&:first)
        Merchant.where(id: aliases.keys).order(:slug).map do |merchant|
          rows = aliases.fetch(merchant.id)
          Entry.new(merchant.slug, merchant.name, rows.select { |_, kind, _| kind == "name" }.map(&:last).sort,
            rows.select { |_, kind, _| kind == "vpa" }.map(&:last).sort)
        end
      end

      attr_reader :catalogue

      def initialize(catalogue:)
        @catalogue = catalogue
      end

      def labels = catalogue.map(&:slug) + [ PERSON, UNKNOWN ]

      def messages(rows)
        [ { role: "system", content: system_message }, { role: "user", content: user_message(rows) } ]
      end

      def schema
        {
          type: "object", additionalProperties: false, required: [ "answers" ],
          properties: {
            answers: {
              type: "array",
              items: {
                type: "object", additionalProperties: false, required: %w[ id label confidence evidence ],
                properties: {
                  id: { type: "string" },
                  label: { type: "string", enum: labels },
                  confidence: { type: "number" },
                  evidence: { type: "string" }
                }
              }
            }
          }
        }
      end

      # What the model sees of a row; the validator checks evidence against
      # the same masked text.
      def self.row_payload(id, parsed)
        { id: id, channel: parsed.channel.to_s, payee: parsed.payee&.squish.presence&.then { |payee| mask(payee) },
          upi_id: (parsed.vpa || parsed.vpa_local)&.then { |vpa| mask(vpa) }, narration: mask(parsed.text.squish) }.compact
      end

      private
        def system_message
          <<~PROMPT
            You identify who is on the other side of Indian bank statement lines (State Bank of India format).
            For each row, answer with exactly one label:
            - a merchant slug from the catalogue below, only when the narration itself names that merchant: its name, a brand, a clear abbreviation or misspelling of it, or one of its UPI IDs;
            - "person" when the money goes to or comes from an individual (a personal name, often with a personal UPI ID);
            - "unknown" for a business that is not in the catalogue, for a payment gateway or aggregator that does not name the merchant (RAZORPAY, PAYU, CASHFREE, PAYTM PAYMENTS, BILLDESK, ...), for an employer paying a salary, or when you cannot tell.
            Never infer a merchant from the amount, the gateway, the city or what is likely. "unknown" is always acceptable; a wrong merchant is not.
            evidence: copy the characters from the row's narration that support the label (the merchant's name or UPI ID, or the person's name). Copy them exactly; do not explain.
            confidence: your probability, from 0 to 1, that the label is right.
            Statement text wraps at a fixed width, so a space can appear anywhere, even inside a word or a UPI ID ("NETF LIX", "raz orpay"). Runs of five or more digits (references, account and phone numbers) are masked as #.
            Answer every row id exactly once, as {"answers": [{"id": ..., "label": ..., "confidence": ..., "evidence": ...}]}.

            Catalogue (slug: display name | names as printed, without spaces | UPI IDs):
            #{catalogue_lines}
          PROMPT
        end

        def catalogue_lines
          catalogue.map { |entry| "#{entry.slug}: #{entry.name} | #{entry.names.join(", ")} | #{entry.vpas.join(", ")}" }.join("\n")
        end

        def user_message(rows)
          "Rows:\n" + rows.map { |row| JSON.generate(self.class.row_payload(row.fetch(:id), row.fetch(:parsed))) }.join("\n")
        end
    end
  end
end
