require "json"

module Evaluation
  # Scores Detection::Engine against labelled synthetic histories
  # (Synthetic::Histories, eval/detection/README.md):
  #
  #   report = Evaluation::RecurringDetection.new(histories).report
  #   report.false_flags   # => { value: 0.004, low: 0.002, high: 0.008, n: 21_000 } (share of debits)
  #   report.series_precision, report.series_recall, ...
  #
  # The headline metric is false flags per 100 charges: of all debits, how
  # many the engine puts in a flagged series (a subscription it would show
  # the household) that are not charges of a real subscription. Next to it:
  #
  #   series precision  flagged series that are one real subscription (at
  #                     least 80% of their charges belong to it, and no
  #                     other flagged series already claimed it)
  #   series recall     detectable real subscriptions found that way
  #   price increases   by the exact first charge at the new price
  #   duplicates        second subscriptions at the same merchant, by the
  #                     pair of series
  #   status            active vs ended, on matched series
  #
  # Intervals are 95% Wilson intervals. Charges cluster by household, so
  # treat the intervals on charge counts as optimistic.
  class RecurringDetection
    MATCH_SHARE = 0.8

    def self.load(path)
      File.readlines(path, chomp: true).reject(&:blank?).map { |line| JSON.parse(line) }
    end

    def initialize(histories, settings: ::Detection.config)
      @histories = histories
      @settings = settings
    end

    def report = Report.new(@histories.map { |history| score(history) })

    # One history's outcome. Lists hold [history id, detail] for error lines.
    Outcome = Data.define(:id, :debits, :flagged, :false_flags, :subscription_charges, :found_charges,
      :predicted, :correct_series, :wrong_series, :detectable, :missed_series,
      :increases, :true_increases, :correct_increases, :duplicates, :true_duplicates, :correct_duplicates,
      :status_checked, :status_correct, :commitments_flagged)

    class Report
      attr_reader :outcomes

      def initialize(outcomes)
        @outcomes = outcomes
      end

      def total(field) = outcomes.sum { |outcome| count(outcome.public_send(field)) }
      def histories = outcomes.size
      def debits = total(:debits)

      def false_flags = RecurringDetection.wilson(total(:false_flags), debits)
      def charge_recall = RecurringDetection.wilson(total(:found_charges), total(:subscription_charges))
      def series_precision = RecurringDetection.wilson(total(:correct_series), total(:predicted))
      def series_recall = RecurringDetection.wilson(total(:correct_series), total(:detectable))
      def increase_precision = RecurringDetection.wilson(total(:correct_increases), total(:increases))
      def increase_recall = RecurringDetection.wilson(total(:correct_increases), total(:true_increases))
      def duplicate_precision = RecurringDetection.wilson(total(:correct_duplicates), total(:duplicates))
      def duplicate_recall = RecurringDetection.wilson(total(:correct_duplicates), total(:true_duplicates))
      def status_accuracy = RecurringDetection.wilson(total(:status_correct), total(:status_checked))

      # False flags by the role of the debit that was wrongly flagged.
      def false_flag_roles = outcomes.flat_map(&:false_flags).map { |detail| detail[:role] }.tally.sort_by { |_, n| -n }.to_h

      def gate_failures(gate)
        checks = {
          "false_flags_per_100_high" => [ per100(false_flags[:high]), :max, "false flags per 100 charges (upper bound)" ],
          "series_precision_low" => [ series_precision[:low], :min, "series precision (lower bound)" ],
          "series_recall" => [ series_recall[:value], :min, "series recall" ],
          "price_increase_precision" => [ increase_precision[:value], :min, "price increase precision" ],
          "price_increase_recall" => [ increase_recall[:value], :min, "price increase recall" ],
          "duplicate_precision" => [ duplicate_precision[:value], :min, "duplicate subscription precision" ],
          "duplicate_recall" => [ duplicate_recall[:value], :min, "duplicate subscription recall" ],
          "status_accuracy" => [ status_accuracy[:value], :min, "status accuracy" ]
        }
        failures = gate.filter_map do |key, limit|
          value, direction, label = checks.fetch(key) { raise ArgumentError, "unknown detection gate #{key}" }
          if value.nil?
            "#{label}: no data"
          elsif direction == :max ? value > limit : value < limit
            "#{label} #{fmt(value, key)} is #{direction == :max ? "above" : "below"} #{fmt(limit, key)}"
          end
        end
        flagged = total(:commitments_flagged)
        failures << "#{flagged} commitments (SIP, EMI, rent, insurance, utilities) flagged" if flagged.positive?
        failures
      end

      def summary_lines
        ff = false_flags
        [
          "False flags: #{per100_text(ff)} per 100 charges (#{total(:false_flags)} of #{debits} debits, #{histories} households)",
          "Series: precision #{interval(series_precision)}, recall #{interval(series_recall)} " \
            "(#{total(:correct_series)} right of #{total(:predicted)} flagged, #{total(:detectable)} detectable)",
          "Charges of real subscriptions flagged: #{interval(charge_recall)}",
          "Price increases: precision #{interval(increase_precision)}, recall #{interval(increase_recall)} " \
            "(#{total(:correct_increases)} right of #{total(:increases)} found, #{total(:true_increases)} real)",
          "Duplicate subscriptions: precision #{interval(duplicate_precision)}, recall #{interval(duplicate_recall)} " \
            "(#{total(:correct_duplicates)} right of #{total(:duplicates)} found, #{total(:true_duplicates)} real)",
          "Status (active/ended) on matched series: #{interval(status_accuracy)}",
          "False flags by role: #{false_flag_roles.map { |role, n| "#{role} #{n}" }.join(", ").presence || "none"}"
        ]
      end

      def error_lines
        lines = []
        outcomes.each do |outcome|
          outcome.wrong_series.each { |detail| lines << "#{outcome.id} wrong series: #{detail}" }
          outcome.missed_series.each { |detail| lines << "#{outcome.id} missed: #{detail}" }
          (outcome.increases - outcome.correct_increases).each { |detail| lines << "#{outcome.id} wrong increase: #{detail}" }
          (outcome.true_increases - outcome.correct_increases).each { |detail| lines << "#{outcome.id} missed increase: #{detail}" }
          (outcome.duplicates - outcome.correct_duplicates).each { |detail| lines << "#{outcome.id} wrong duplicate: #{detail}" }
          (outcome.true_duplicates - outcome.correct_duplicates).each { |detail| lines << "#{outcome.id} missed duplicate: #{detail}" }
        end
        lines
      end

      def to_h
        { histories: histories, debits: debits, false_flags: false_flags, false_flags_per_100: per100(false_flags[:value]),
          false_flag_roles: false_flag_roles, series_precision: series_precision, series_recall: series_recall,
          charge_recall: charge_recall, price_increase_precision: increase_precision, price_increase_recall: increase_recall,
          duplicate_precision: duplicate_precision, duplicate_recall: duplicate_recall, status_accuracy: status_accuracy }
      end

      def pct(value) = value.nil? ? "n/a" : format("%.1f%%", value * 100)

      private
        def count(value) = value.is_a?(Array) ? value.size : value
        def per100(share) = share && (share * 100).round(3)
        def per100_text(score) = score[:value].nil? ? "n/a" : format("%.2f [%.2f, %.2f]", *score.values_at(:value, :low, :high).map { |v| v * 100 })
        def fmt(value, key) = key.start_with?("false_flags") ? format("%.2f", value) : pct(value)

        def interval(score)
          return "n/a" if score[:value].nil?

          "#{pct(score[:value])} [#{pct(score[:low])}, #{pct(score[:high])}]"
        end
    end

    def self.wilson(successes, trials) = MerchantResolution.wilson(successes, trials)

    private
      def score(history)
        as_of = Date.iso8601(history.fetch("as_of"))
        rows = history.fetch("txns").map do |id, merchant, category, on, amount, key, role|
          { txn: ::Detection::Txn.new(id, merchant, category, Date.iso8601(on), amount), key: key, role: role }
        end
        label = rows.to_h { |row| [ row[:txn].id, row ] }
        truth = history.fetch("series")
        result = ::Detection::Engine.new(as_of: as_of, settings: @settings).call(rows.map { |row| row[:txn] })

        flagged = result.series.select(&:flagged)
        subscription = ->(key) { key && truth.dig(key, "kind") == "subscription" }
        flagged_charges = flagged.flat_map(&:charges)
        false_flags = flagged_charges.reject { |charge| subscription.(label.fetch(charge.id)[:key]) }
          .map { |charge| { id: charge.id, role: label.fetch(charge.id)[:role], key: label.fetch(charge.id)[:key] } }

        detectable = truth.select { |_, info| info["detectable"] }.keys
        subscription_ids = rows.select { |row| detectable.include?(row[:key]) }.map { |row| row[:txn].id }
        flagged_ids = flagged_charges.to_set(&:id)

        matched = {}
        wrong = []
        flagged.each do |series|
          keys = series.charges.map { |charge| label.fetch(charge.id)[:key] }
          key, hits = keys.compact.tally.max_by { |_, n| n }
          if key && subscription.(key) && hits >= MATCH_SHARE * keys.size && !matched.value?(key)
            matched[series] = key
          else
            wrong << describe(series, keys)
          end
        end
        missed = detectable - matched.values

        findings = result.findings
        active_detectable = ->(key) { key && truth.dig(key, "detectable") && truth.dig(key, "status") == "active" }
        increases = findings.select { |f| f.kind == "price_increase" }.map { |f| "#{f.series.merchant} step at txn #{f.step_charge.id}" }
        true_increases = truth.select { |key, info| active_detectable.(key) && info["increase"] }
          .map { |_, info| "#{info["merchant"]} step at txn #{info.dig("increase", "txn")}" }
        duplicates = findings.select { |f| f.kind == "duplicate" }.map do |f|
          "#{matched[f.series] || "#{f.series.merchant} (unmatched)"} duplicates #{matched[f.related] || "#{f.related.merchant} (unmatched)"}"
        end
        true_duplicates = truth.select { |key, info| active_detectable.(key) && active_detectable.(info["duplicate_of"]) }
          .map { |key, info| "#{key} duplicates #{info["duplicate_of"]}" }

        status_pairs = matched.map { |series, key| [ series.status, truth.dig(key, "status") ] }
        commitments = flagged.count { |series| series.charges.any? { |c| truth.dig(label.fetch(c.id)[:key], "kind") == "commitment" } }

        Outcome.new(
          id: history.fetch("id"), debits: rows.count { |row| row[:txn].amount_paise.negative? },
          flagged: flagged_charges.size, false_flags: false_flags,
          subscription_charges: subscription_ids.size, found_charges: subscription_ids.count { |id| flagged_ids.include?(id) },
          predicted: flagged.size, correct_series: matched.size, wrong_series: wrong,
          detectable: detectable.size, missed_series: missed.map { |key| "#{key} (#{truth[key].values_at("cadence", "status", "charges").join(", ")} charges)" },
          increases: increases, true_increases: true_increases, correct_increases: increases & true_increases,
          duplicates: duplicates, true_duplicates: true_duplicates, correct_duplicates: duplicates & true_duplicates,
          status_checked: status_pairs.size, status_correct: status_pairs.count { |got, want| got == want },
          commitments_flagged: commitments
        )
      end

      def describe(series, keys)
        labels = keys.map { |key| key || "-" }.tally.map { |key, n| "#{key}×#{n}" }.join(" ")
        "#{series.merchant} #{series.cadence.name} #{series.status} ₹#{series.amount_paise / 100} " \
          "#{series.first_charged_on}..#{series.last_charged_on} [#{labels}]"
      end
  end
end
