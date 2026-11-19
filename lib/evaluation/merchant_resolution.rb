require "json"
require "digest"

module Evaluation
  # Scores a narration resolver against a labelled JSONL set (see
  # eval/merchant_resolution/README.md):
  #
  #   report = Evaluation::MerchantResolution.new(examples, resolver: Merchants::Resolver.new).report
  #   report.merchant[:accuracy]  # => { value: 0.97, low: 0.94, high: 0.985 }
  #   report.merchant[:coverage]  # => { value: 0.81, ... }
  #
  # The headline metric is merchant accuracy at a stated coverage, over rows
  # whose true counterparty is a business (a catalogue merchant or "unknown"):
  #
  #   coverage = answered / merchant rows        (abstaining is allowed...)
  #   accuracy = correct / answered              (...guessing wrong is not)
  #
  # An "unknown" business can only be answered wrongly, so abstaining on it
  # costs coverage but not accuracy. Intervals are 95% Wilson score
  # intervals: the golden set is a sample, and 300 rows can't tell 97% from
  # 98%.
  class MerchantResolution
    Row = Data.define(:id, :narration, :amount_paise, :label, :channel, :noise, :predicted, :via, :evidence) do
      def answered? = predicted != "abstain"
      def correct? = predicted == label
      def business? = !NON_MERCHANT.include?(label)
    end

    NON_MERCHANT = %w[ person bank cash ].freeze
    Z = 1.96

    def self.load(path)
      File.readlines(path, chomp: true).reject(&:blank?).map { |line| JSON.parse(line, symbolize_names: true) }
    end

    def self.wilson(successes, trials)
      return { value: nil, low: nil, high: nil, n: 0 } if trials.zero?

      p = successes.fdiv(trials)
      denominator = 1 + Z**2 / trials
      centre = (p + Z**2 / (2 * trials)) / denominator
      margin = Z * Math.sqrt(p * (1 - p) / trials + Z**2 / (4 * trials**2)) / denominator
      { value: p.round(4), low: (centre - margin).clamp(0, 1).round(4), high: (centre + margin).clamp(0, 1).round(4), n: trials }
    end

    def initialize(examples, resolver:)
      @examples = examples
      @resolver = resolver
    end

    # A resolver with resolve_many (Merchants::LlmResolver) gets every
    # narration at once, so it can batch its LLM requests.
    def rows
      @rows ||= begin
        results = if @resolver.respond_to?(:resolve_many)
          @resolver.resolve_many(@examples.map { |example| example.fetch(:narration) })
        else
          @examples.map { |example| @resolver.resolve(example.fetch(:narration), amount_paise: example[:amount_paise]) }
        end
        @examples.zip(results).map do |example, result|
          Row.new(**example.slice(:id, :narration, :amount_paise, :label, :channel).merge(noise: Array(example[:noise])),
            predicted: result.label, via: result.via, evidence: result.evidence)
        end
      end
    end

    def report = Report.new(rows)

    class Report
      attr_reader :rows

      def initialize(rows)
        @rows = rows
      end

      def merchant = scores(rows.select(&:business?))
      def overall = scores(rows)

      # Of the rows whose merchant is in the catalogue, how many were named correctly.
      def catalogue_recall
        known = rows.select { |row| row.business? && row.label != "unknown" }
        MerchantResolution.wilson(known.count(&:correct?), known.size)
      end

      def by_channel
        rows.group_by(&:channel).sort.to_h.transform_values do |group|
          answered = group.select(&:answered?)
          { n: group.size, answered: answered.size, correct: answered.count(&:correct?) }
        end
      end

      def by_method
        rows.select(&:answered?).group_by(&:via).sort.to_h.transform_values do |group|
          { answered: group.size, correct: group.count(&:correct?) }
        end
      end

      def errors = rows.select { |row| row.answered? && !row.correct? }
      def abstentions = rows.reject(&:answered?)

      def gate_failures(gate)
        failures = []
        accuracy, coverage = merchant.values_at(:accuracy, :coverage)
        if accuracy[:low].nil? || accuracy[:low] < gate.fetch("merchant_accuracy_low")
          failures << "merchant accuracy 95% lower bound #{pct(accuracy[:low])} < #{pct(gate["merchant_accuracy_low"])}"
        end
        if coverage[:value].nil? || coverage[:value] < gate.fetch("merchant_coverage")
          failures << "merchant coverage #{pct(coverage[:value])} < #{pct(gate["merchant_coverage"])}"
        end
        failures
      end

      # Correct answers minus `cost` per wrong answer: abstaining scores 0,
      # so answering only pays when the answers are right often enough.
      def net_score(group = rows, cost:)
        answered = group.select(&:answered?)
        answered.count(&:correct?) - cost * answered.count { |row| !row.correct? }
      end

      # Rules + LLM must beat rules only on the same rows (config/eval.yml llm_gate).
      def beat_failures(baseline, gate)
        cost = gate.fetch("wrong_answer_cost")
        failures = []
        accuracy = merchant[:accuracy]
        if accuracy[:low].nil? || accuracy[:low] < gate.fetch("merchant_accuracy_low")
          failures << "merchant accuracy 95% lower bound #{pct(accuracy[:low])} < #{pct(gate["merchant_accuracy_low"])}"
        end
        if merchant[:answered] < baseline.merchant[:answered]
          failures << "answers fewer business rows (#{merchant[:answered]}) than rules only (#{baseline.merchant[:answered]})"
        end
        business = net_score(rows.select(&:business?), cost: cost)
        base_business = baseline.net_score(baseline.rows.select(&:business?), cost: cost)
        if business < base_business
          failures << "business-row net score #{business} < rules only #{base_business} (a wrong answer costs #{cost})"
        end
        overall = net_score(cost: cost)
        base_overall = baseline.net_score(cost: cost)
        failures << "net score #{overall} doesn't beat rules only (#{base_overall}; a wrong answer costs #{cost})" if overall <= base_overall
        failures
      end

      def comparison_line(baseline, cost:)
        gained = rows.zip(baseline.rows).select { |row, base| row.answered? && !base.answered? }.map(&:first)
        "vs rules only: #{gained.size} more answered (#{gained.count(&:correct?)} correct, #{gained.count { |row| !row.correct? }} wrong); " \
          "net score #{net_score(cost: cost)} vs #{baseline.net_score(cost: cost)} (a wrong answer costs #{cost})"
      end

      def to_h
        { rows: rows.size, merchant: merchant, overall: overall, catalogue_recall: catalogue_recall,
          by_channel: by_channel, by_method: by_method, errors: errors.size, abstentions: abstentions.size }
      end

      def summary_lines
        m = merchant
        o = overall
        [
          "Merchant accuracy #{interval(m[:accuracy])} at coverage #{interval(m[:coverage])} (#{m[:rows]} business rows)",
          "Catalogue recall  #{interval(catalogue_recall)}",
          "Overall accuracy  #{interval(o[:accuracy])} at coverage #{interval(o[:coverage])} (#{o[:rows]} rows, " \
            "incl. person/bank/cash)",
          "Wrong answers: #{errors.size}; abstentions: #{abstentions.size}"
        ]
      end

      def channel_table
        lines = [ "| channel | rows | answered | correct |", "|---|---:|---:|---:|" ]
        by_channel.each { |channel, s| lines << "| #{channel} | #{s[:n]} | #{s[:answered]} | #{s[:correct]} |" }
        lines
      end

      def error_lines(limit: nil)
        list = limit ? errors.first(limit) : errors
        list.map { |row| "#{row.id} [#{row.channel}] expected #{row.label}, got #{row.predicted} via #{row.via}: #{row.narration}" }
      end

      def abstention_lines(limit: nil)
        list = limit ? abstentions.first(limit) : abstentions
        list.map { |row| "#{row.id} [#{row.channel}] #{row.label}: #{row.evidence} | #{row.narration}" }
      end

      def pct(value) = value.nil? ? "n/a" : format("%.1f%%", value * 100)

      private
        def scores(group)
          answered = group.select(&:answered?)
          { rows: group.size, answered: answered.size, correct: answered.count(&:correct?),
            coverage: MerchantResolution.wilson(answered.size, group.size),
            accuracy: MerchantResolution.wilson(answered.count(&:correct?), answered.size) }
        end

        def interval(score)
          return "n/a" if score[:value].nil?
          "#{pct(score[:value])} [#{pct(score[:low])}, #{pct(score[:high])}]"
        end
    end
  end
end
