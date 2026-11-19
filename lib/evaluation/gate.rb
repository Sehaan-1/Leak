require "digest"

module Evaluation
  # Runs the merchant-resolution eval for `bin/rails leak:eval:merchants`.
  #
  # golden: the frozen set. Checks its hash, prints aggregate scores only (so
  #         nobody tunes rules against individual golden rows) and enforces
  #         the gate in config/eval.yml.
  # dev:    the tuning set. Prints every wrong answer and abstention.
  #
  # Writes tmp/eval/merchant_resolution-<set>.json and, on GitHub Actions,
  # a job summary. Returns a process exit status.
  module Gate
    module_function

    def config
      YAML.safe_load_file(Rails.root.join("config/eval.yml")).fetch("merchant_resolution")
    end

    def run(set:, out: $stdout)
      settings = config
      path = Rails.root.join(settings.fetch(set) { raise ArgumentError, "unknown eval set #{set.inspect}" })
      golden = set == "golden"
      if golden && (actual = Digest::SHA256.file(path).hexdigest) != settings["golden_sha256"]
        out.puts "✗ #{path.relative_path_from(Rails.root)} changed (sha256 #{actual}); the golden set is frozen."
        return 1
      end

      Merchants::Catalogue.sync!
      report = MerchantResolution.new(MerchantResolution.load(path), resolver: Merchants::Resolver.new).report
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
      failures.empty? ? 0 : 1
    end

    # Workflow commands, so the scores (or the failure) show on the PR.
    def annotate(out, set, report, failures)
      failures.each { |failure| out.puts "\n::error title=Merchant eval gate failed::#{failure}" }
      out.puts "\n::notice title=Merchant resolution (rules only%2C #{set})::#{report.summary_lines.first}"
    end

    def write_outputs(set, report, failures)
      dir = Rails.root.join("tmp/eval")
      FileUtils.mkdir_p(dir)
      File.write(dir.join("merchant_resolution-#{set}.json"), JSON.pretty_generate(report.to_h.merge(gate_failures: failures)))
      return unless (summary = ENV["GITHUB_STEP_SUMMARY"])

      File.open(summary, "a") do |file|
        file.puts "### Merchant resolution (rules only, #{set} set)", ""
        report.summary_lines.each { |line| file.puts "- #{line}" }
        file.puts "", *report.channel_table, ""
        file.puts(failures.any? ? "**Gate failed:** #{failures.join("; ")}" : "Gate: passed") if set == "golden"
        file.puts ""
      end
    end
  end
end
