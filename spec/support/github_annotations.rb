# On GitHub Actions, report each failure as an error annotation so it shows
# on the PR diff (and in the checks API) without opening the job log.
class GithubAnnotationsFormatter
  RSpec::Core::Formatters.register self, :example_failed, :message

  def initialize(output)
    @output = output
  end

  def example_failed(notification)
    example = notification.example
    file, line = location(example, notification.exception)
    message = notification.fully_formatted(1, RSpec::Core::Notifications::NullColorizer)
    # Workflow commands must start a line; progress dots don't end one.
    @output.puts "\n::error file=#{file},line=#{line},title=#{escape_property(example.full_description)}::#{escape(message)}"
  end

  # Errors outside examples (a spec file that fails to load) arrive as messages.
  def message(notification)
    return unless notification.message.match?(/error occurred|Error/)

    @output.puts "\n::error title=RSpec::#{escape(notification.message)}"
  end

  private
    # Prefer the deepest frame inside the spec file itself, else the example's line.
    def location(example, exception)
      spec_file = example.metadata[:file_path].delete_prefix("./")
      frame = Array(exception&.backtrace).find { |f| f.include?(spec_file) }
      line = frame&.match(/:(\d+)/)&.[](1) || example.metadata[:line_number]
      [ spec_file, line ]
    end

    def escape(text)
      text.to_s.gsub("%", "%25").gsub("\r", "%0D").gsub("\n", "%0A")
    end

    def escape_property(text)
      escape(text).gsub(":", "%3A").gsub(",", "%2C")
    end
end

RSpec.configure { |config| config.add_formatter(GithubAnnotationsFormatter, $stdout) } if ENV["GITHUB_ACTIONS"]
