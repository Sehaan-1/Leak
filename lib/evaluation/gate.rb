require "digest"

module Evaluation
  # Runs the merchant-resolution eval for `bin/rails leak:eval:merchants`.
  #
  # golden: the frozen set. Checks its hash, prints aggregate scores only (so
  #         nobody tunes rules against individual golden rows) and enforces
  #         the gate in config/eval.yml.
  # dev:    the tuning set. Prints every wrong answer and abstention.
  #
  # With LLM_EVAL set it also runs rules + LLM (Merchants::LlmResolver) on
  # the same rows, and on golden requires it to beat rules only (llm_gate):
  #
  #   replay  recorded replies (eval/merchant_resolution/replay/), offline;
  #           a stale recording fails, a missing one skips the LLM gate.
  #           CI runs this on every PR.
  #   live    the configured provider (LLM_PROVIDER, config/llm.yml).
  #   record  live, then saves the replies as the new recording.
  #
  # Writes tmp/eval/merchant_resolution-<set>[-llm].json and, on GitHub
  # Actions, a job summary. Returns a process exit status.
  module Gate
    MODES = %w[ replay live record ].freeze

    module_function

    def config
      YAML.safe_load_file(Rails.root.join("config/eval.yml")).fetch("merchant_resolution")
    end

    def run(set:, out: $stdout, llm: ENV["LLM_EVAL"].presence)
      raise ArgumentError, "LLM_EVAL must be one of #{MODES.join(", ")}" if llm && !MODES.include?(llm)

      settings = config
      path = Rails.root.join(settings.fetch(set) { raise ArgumentError, "unknown eval set #{set.inspect}" })
      golden = set == "golden"
      if golden && (actual = Digest::SHA256.file(path).hexdigest) != settings["golden_sha256"]
        out.puts "✗ #{path.relative_path_from(Rails.root)} changed (sha256 #{actual}); the golden set is frozen."
        return 1
      end

      Merchants::Catalogue.sync!
      examples = MerchantResolution.load(path)
      report = MerchantResolution.new(examples, resolver: Merchants::Resolver.new).report
      failures = golden ? report.gate_failures(settings.fetch("gate")) : []

      out.puts "Merchant resolution, rules only, #{set} set (#{path.relative_path_from(Rails.root)})"
      report.summary_lines.each { |line| out.puts "  #{line}" }
      out.puts(*report.channel_table)
      out.puts "By method: #{report.by_method.map { |via, s| "#{via} #{s[:correct]}/#{s[:answered]}" }.join(", ")}"
      unless golden
        out.puts "", "Wrong answers:", *report.error_lines
        out.puts "", "Abstentions:", *report.abstention_lines
      end
      failures.each { |failure| out.puts "✗ Gate: #{failure}" }
      annotate(out, set, report, failures) if ENV["GITHUB_ACTIONS"]
      out.puts "✓ Gate passed (#{settings["gate"].map { |k, v| "#{k} #{v}" }.join(", ")})" if golden && failures.empty?

      write_outputs(set, report, failures)
      status = failures.empty? ? 0 : 1
      llm ? [ status, run_llm(set: set, mode: llm, examples: examples, baseline: report, out: out) ].max : status
    end

    def replay_path(set) = Rails.root.join("eval/merchant_resolution/replay", "#{File.basename(config.fetch(set), ".jsonl")}.json")

    def llm_client(set, mode)
      return Merchants::Llm::ReplayClient.new(replay_path(set)) if mode == "replay"

      live = Merchants::Llm.client
      raise Merchants::Llm::ConfigurationError, "LLM_EVAL=#{mode} needs a provider: set LLM_PROVIDER (config/llm.yml)" unless live.enabled?
      mode == "record" ? Merchants::Llm::ReplayClient.new(replay_path(set), record: live) : live
    end

    def run_llm(set:, mode:, examples:, baseline:, out:)
      golden = set == "golden"
      gate = config.fetch("llm_gate")
      if mode == "replay" && !replay_path(set).exist?
        message = "no recorded LLM replies for #{set} yet, so the LLM gate is off. Record them with any provider: " \
          "LLM_EVAL=record LLM_PROVIDER=... bin/rails 'leak:eval:merchants[#{set}]'"
        out.puts "", "• #{message}"
        out.puts "\n::notice title=LLM eval skipped::#{message}" if ENV["GITHUB_ACTIONS"]
        return 0
      end
      client = llm_client(set, mode)
      report = MerchantResolution.new(examples, resolver: Merchants::LlmResolver.new(client: client)).report
      if client.respond_to?(:recording?) && client.recording?
        client.save!(prompt_version: Merchants::Llm.settings.fetch("prompt_version"))
        out.puts "✓ Recorded #{client.path.relative_path_from(Rails.root)}"
      end
      failures = golden ? report.beat_failures(baseline, gate) : []
      title = "rules + LLM (#{client.model || client.name}, #{mode})"

      out.puts "", "Merchant resolution, #{title}, #{set} set"
      report.summary_lines.each { |line| out.puts "  #{line}" }
      out.puts "  #{report.comparison_line(baseline, cost: gate.fetch("wrong_answer_cost"))}"
      out.puts(*report.channel_table)
      out.puts "By method: #{report.by_method.map { |via, s| "#{via} #{s[:correct]}/#{s[:answered]}" }.join(", ")}"
      unless golden
        llm_rows = report.rows.select { |row| row.via == "llm" || row.evidence.to_s.start_with?("LLM") }
        out.puts "", "LLM answers and rejections:"
        llm_rows.each do |row|
          out.puts "#{row.id} [#{row.channel}] #{row.label} -> #{row.predicted} (#{row.via}): #{row.evidence} | #{row.narration}"
        end
      end
      failures.each { |failure| out.puts "✗ LLM gate: #{failure}" }
      out.puts "✓ LLM gate passed: rules + LLM beats rules only" if golden && failures.empty?
      if ENV["GITHUB_ACTIONS"]
        failures.each { |failure| out.puts "\n::error title=LLM eval gate failed::#{failure}" }
        out.puts "\n::notice title=Merchant resolution (#{escape(title)}%2C #{set})::#{report.summary_lines.first}"
      end

      write_outputs(set, report, failures, suffix: "-llm", title: title)
      failures.empty? ? 0 : 1
    rescue Merchants::Llm::ReplayClient::Miss => error
      message = "the LLM replay for #{set} is stale (#{error.message}): the prompt, catalogue or rows changed. " \
        "Record it again with any provider: LLM_EVAL=record LLM_PROVIDER=... bin/rails 'leak:eval:merchants[#{set}]', " \
        "or run the LLM eval workflow with record=true."
      out.puts "✗ #{message}"
      out.puts "\n::error title=LLM replay is stale::#{message}" if ENV["GITHUB_ACTIONS"]
      1
    end

    # Workflow command properties can't hold "," or ":" as such.
    def escape(text) = text.gsub("%", "%25").gsub(",", "%2C").gsub(":", "%3A")

    # Workflow commands, so the scores (or the failure) show on the PR.
    def annotate(out, set, report, failures)
      failures.each { |failure| out.puts "\n::error title=Merchant eval gate failed::#{failure}" }
      out.puts "\n::notice title=Merchant resolution (rules only%2C #{set})::#{report.summary_lines.first}"
    end

    def write_outputs(set, report, failures, suffix: "", title: "rules only")
      dir = Rails.root.join("tmp/eval")
      FileUtils.mkdir_p(dir)
      File.write(dir.join("merchant_resolution-#{set}#{suffix}.json"), JSON.pretty_generate(report.to_h.merge(gate_failures: failures)))
      return unless (summary = ENV["GITHUB_STEP_SUMMARY"])

      File.open(summary, "a") do |file|
        file.puts "### Merchant resolution (#{title}, #{set} set)", ""
        report.summary_lines.each { |line| file.puts "- #{line}" }
        file.puts "", *report.channel_table, ""
        file.puts(failures.any? ? "**Gate failed:** #{failures.join("; ")}" : "Gate: passed") if set == "golden"
        file.puts ""
      end
    end
  end
end
