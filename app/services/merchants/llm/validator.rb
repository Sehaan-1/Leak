module Merchants
  module Llm
    # Decides whether an LLM answer for one row may stand. Anything that
    # fails a check becomes an abstention (the row goes to review), with the
    # reason as evidence:
    #
    # - the label is a catalogue slug or "person" ("unknown" is an honest
    #   abstention: a business the catalogue lacks);
    # - the confidence is at least min_confidence;
    # - the evidence is really in the narration (compared space-free, as the
    #   rules do), so the model can't quote what isn't there;
    # - a merchant: the longest catalogue name (or UPI ID) inside the
    #   evidence is its own; or, if none is, its names are the closest
    #   trigram match to the evidence of all merchants (ties allowed) at
    #   min_evidence_similarity or more. "HDFC STANDARD LIFE" may be HDFC
    #   Life (0.37), not HDFC Mutual Fund (0.20);
    # - a person: a transfer or UPI payment whose payee reads like a personal
    #   name and whose UPI ID isn't a merchant's (as in the rules), and the
    #   evidence is that name.
    class Validator
      Verdict = Data.define(:label, :accepted, :evidence) do
        def accepted? = accepted
      end

      def initialize(catalogue:, min_confidence:, min_similarity:)
        @catalogue = catalogue.index_by(&:slug)
        @keys = catalogue.to_h do |entry|
          [ entry.slug, (entry.names + entry.vpas.map { |vpa| Text.key(vpa.split("@").first) }).select { |key| key.length >= 3 }.uniq ]
        end
        @min_confidence = min_confidence
        @min_similarity = min_similarity
      end

      # answer: one element of the reply's "answers" (string keys), or nil.
      def check(answer, parsed)
        return reject("no answer for this row") unless answer.is_a?(Hash)

        label = answer["label"].to_s
        confidence = answer["confidence"]
        evidence = answer["evidence"].to_s.squish
        return reject("label #{label.inspect} is not in the catalogue") unless @catalogue.key?(label) || label.in?([ Prompt::PERSON, Prompt::UNKNOWN ])
        return reject("not in the catalogue: #{evidence.presence || "no evidence"}") if label == Prompt::UNKNOWN
        return reject("confidence #{confidence.inspect} is below #{@min_confidence}") unless confidence.is_a?(Numeric) && confidence >= @min_confidence

        key = Text.key(evidence)
        narration = Text.key(Prompt.mask(parsed.text))
        return reject("evidence #{evidence.inspect} is not in the narration") if key.length < 3 || !narration.include?(key)

        label == Prompt::PERSON ? person(parsed, evidence, key) : merchant(label, evidence, key)
      end

      private
        def merchant(slug, evidence, key)
          # The longest catalogue name inside the evidence wins ("JIOHOTSTAR" is JioHotstar, not Jio).
          contained = @keys.transform_values { |names| names.select { |name| key.include?(name) }.map(&:length).max || 0 }
          longest = contained.values.max.to_i
          if longest.positive?
            return accept(slug, "LLM: #{evidence} names #{@catalogue[slug].name}") if contained.fetch(slug) == longest

            other = contained.key(longest)
            return reject("LLM said #{slug}, but #{evidence.inspect} names #{@catalogue[other].name}")
          end

          scores = @keys.transform_values { |names| names.map { |name| Text.similarity(key, name) }.max || 0.0 }
          score = scores.fetch(slug)
          if score >= @min_similarity && score >= scores.values.max
            return accept(slug, format("LLM: %s resembles %s (similarity %.2f)", evidence, @catalogue[slug].name, score))
          end

          reject(format("LLM said %s, but %s doesn't match its names (similarity %.2f)", slug, evidence.inspect, score))
        end

        def person(parsed, evidence, key)
          payee = Text.key(parsed.payee)
          vpa = (parsed.vpa || parsed.vpa_local).to_s
          return reject("LLM said person, but this isn't a UPI payment or transfer") unless parsed.channel.in?(%i[ upi neft imps ])
          return reject("LLM said person, but the payee doesn't read like a personal name") unless Resolver.personal_name?(parsed.payee)
          return reject("LLM said person, but #{vpa} is a merchant UPI ID") if vpa.match?(Resolver::MERCHANT_VPA)
          return reject("LLM said person, but #{evidence.inspect} isn't the payee") unless payee.include?(key) || key.include?(payee)

          accept(Prompt::PERSON, "LLM: #{evidence} is an individual")
        end

        def accept(label, evidence) = Verdict.new(label, true, evidence)
        def reject(reason) = Verdict.new(nil, false, "LLM abstained: #{reason}")
    end
  end
end
