require "open3"
require "tmpdir"

module Merchants
  module Llm
    # A coding agent installed on this machine, run headless with whatever
    # model and login it already has:
    #
    #   agy -p PROMPT --output-format json --json-schema SCHEMA   (Antigravity)
    #   opencode run PROMPT                                       (opencode)
    #
    # Runs in an empty temporary directory, so the agent has no files to
    # read or edit, and is killed after `timeout` seconds.
    class CliClient
      attr_reader :model, :name

      def self.installed?(command, env = ENV)
        env.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
          path = File.join(dir, command)
          File.file?(path) && File.executable?(path)
        end
      end

      # runner: ->(argv, timeout) { [stdout, stderr, success] }, for specs.
      def initialize(command:, model: nil, timeout: 90, runner: nil)
        raise ConfigurationError, "unsupported agent #{command.inspect}" unless %w[ agy opencode ].include?(command)

        @command = command
        @model = model
        @name = command
        @timeout = timeout
        @runner = runner || method(:run)
      end

      def enabled? = true

      def complete(messages:, schema:)
        prompt = messages.map { |message| message.fetch(:content) }.join("\n\n")
        prompt += "\n\nReply with one JSON object and nothing else. It must match this JSON schema:\n#{JSON.generate(schema)}"
        stdout, _stderr, success = @runner.call(argv(prompt, schema), @timeout)
        raise Error, "#{@command} failed (is it logged in? run it once interactively)" unless success

        @command == "agy" ? agy_reply(stdout) : stdout
      end

      private
        def argv(prompt, schema)
          if @command == "agy"
            [ "agy", "-p", prompt, "--output-format", "json", "--json-schema", JSON.generate(schema),
              "--print-timeout", "#{@timeout}s", *(@model ? [ "--model", @model ] : []) ]
          else
            [ "opencode", "run", *(@model ? [ "-m", @model ] : []), prompt ]
          end
        end

        # {"status": "SUCCESS", "response": "...", "structured_output": {...}}
        def agy_reply(stdout)
          envelope = Llm.parse_json(stdout)
          raise Error, "agy returned status #{envelope["status"].inspect}" if envelope["status"] && envelope["status"] != "SUCCESS"

          structured = envelope["structured_output"]
          structured.is_a?(Hash) ? JSON.generate(structured) : envelope["response"].to_s
        end

        def run(argv, timeout)
          Dir.mktmpdir("leak-llm") do |dir|
            Open3.popen3(*argv, chdir: dir) do |stdin, stdout, stderr, wait|
              stdin.close
              out = Thread.new { stdout.read }
              err = Thread.new { stderr.read }
              unless wait.join(timeout + 5)
                Process.kill("TERM", wait.pid)
                Process.kill("KILL", wait.pid) unless wait.join(5)
                [ out, err ].each { |reader| reader.join(1) }
                raise Error, "#{argv.first} timed out after #{timeout}s"
              end
              [ out.value, err.value, wait.value.success? ]
            end
          end
        rescue Errno::ENOENT
          raise Error, "#{argv.first} isn't installed"
        end
    end
  end
end
