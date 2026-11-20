require "digest"

module Merchants
  module Llm
    # Recorded LLM replies, so the eval runs offline and deterministically in
    # CI (eval/merchant_resolution/replay/<set>.json):
    #
    #   ReplayClient.new(path)                         # replay; a new request raises Miss
    #   ReplayClient.new(path, record: live_client)    # call the live model, then #save!
    #
    # Requests are keyed by a hash of the messages and schema, so changing
    # the prompt, the catalogue or the rows makes the recording stale (a
    # Miss) until it's recorded again. Eval sets are synthetic: recordings
    # of real narrations must never be made.
    class ReplayClient
      class Miss < Error; end

      attr_reader :path

      def self.key(messages, schema) = Digest::SHA256.hexdigest(JSON.generate([ messages, schema ]))

      def initialize(path, record: nil)
        @path = Pathname(path)
        @live = record
        @data = @path.exist? ? JSON.parse(@path.read) : {}
        @replies = record ? {} : @data.fetch("replies", {})
      end

      def enabled? = true
      def name = @live ? "#{@live.name} (recording)" : "replay"
      def model = @live ? @live.model : @data["model"]
      def recording? = !@live.nil?

      def complete(messages:, schema:)
        key = self.class.key(messages, schema)
        return @replies.fetch(key) { raise Miss, "no recorded reply for request #{key.first(12)} in #{@path.basename}" } unless @live

        @replies[key] = @live.complete(messages: messages, schema: schema)
      end

      def save!(prompt_version:)
        raise Error, "only a recording client can be saved" unless @live

        @path.dirname.mkpath
        @path.write(JSON.pretty_generate({ "provider" => @live.name, "model" => @live.model, "prompt_version" => prompt_version,
                                           "recorded_on" => Date.current.iso8601, "replies" => @replies.sort.to_h }) + "\n")
      end
    end
  end
end
