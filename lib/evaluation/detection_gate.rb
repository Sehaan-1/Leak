require "digest"

module Evaluation
  # Runs the recurring-detection eval for `bin/rails leak:eval:detection`.
  #
  # golden: the frozen set. Checks its hash, prints aggregate scores only and
  #         enforces the gate in config/eval.yml (detection.gate).
  # dev:    the tuning set. Also prints every wrong or missed series,
  #         increase and duplicate.
  #
  # Writes tmp/eval/detection-<set>.json and, on GitHub Actions, a job
  # summary and an annotation. Returns a process exit status.
  module DetectionGate
    module_function

    def config
      YAML.safe_load_file(Rails.root.join("config/eval.yml")).fetch("detection")
    end

    def run(set:, out: $stdout)
      settings = config
      path = Rails.root.join(settings.fetch(set) { raise ArgumentError, "unknown eval set #{set.inspect}" })
      golden = set == "golden"
      if golden && (actual = Digest::SHA256.file(path).hexdigest) != settings["golden_sha256"]
        out.puts "✗ #{path.relative_path_from(Rails.root)} changed (sha256 #{actual}); the golden set is frozen."
        return 1
      end

      report = RecurringDetection.new(RecurringDetection.load(path)).report
      failures = golden ? report.gate_failures(settings.fetch("gate")) : []

      out.puts "Recurring-charge detection, #{set} set (#{path.relative_path_from(Rails.root)})"
      report.summary_lines.each { |line| out.puts "  #{line}" }
      out.puts "", "Errors:", *report.error_lines unless golden
      failures.each { |failure| out.puts "✗ Gate: #{failure}" }
      out.puts "✓ Gate passed (#{settings["gate"].map { |k, v| "#{k} #{v}" }.join(", ")})" if golden && failures.empty?
      if ENV["GITHUB_ACTIONS"]
        failures.each { |failure| out.puts "\n::error title=Detection eval gate failed::#{failure}" }
        out.puts "\n::notice title=Recurring-charge detection (#{set})::#{report.summary_lines.first(2).join(" | ")}"
      end

      write_outputs(set, report, failures)
      failures.empty? ? 0 : 1
    end

    def write_outputs(set, report, failures)
      dir = Rails.root.join("tmp/eval")
      FileUtils.mkdir_p(dir)
      File.write(dir.join("detection-#{set}.json"), JSON.pretty_generate(report.to_h.merge(gate_failures: failures)))
      return unless (summary = ENV["GITHUB_STEP_SUMMARY"])

      File.open(summary, "a") do |file|
        file.puts "### Recurring-charge detection (#{set} set)", ""
        report.summary_lines.each { |line| file.puts "- #{line}" }
        file.puts ""
        file.puts(failures.any? ? "**Gate failed:** #{failures.join("; ")}" : "Gate: passed") if set == "golden"
        file.puts ""
      end
    end
  end
end
