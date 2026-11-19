# A stand-in LLM for specs: answers each row of a request with whatever the
# block returns for its payload (a Hash, or nil to leave the row out).
#
#   client = FakeLlm.new { |row| { "id" => row["id"], "label" => "unknown", "confidence" => 1, "evidence" => "" } }
class FakeLlm
  attr_reader :requests

  def initialize(&responder)
    @responder = responder || ->(_row) { nil }
    @requests = []
  end

  def enabled? = true
  def name = "fake"
  def model = "fake-model"

  def complete(messages:, schema:)
    @requests << { messages: messages, schema: schema }
    JSON.generate("answers" => self.class.rows(messages).filter_map { |row| @responder.call(row) })
  end

  # The row payloads of a request (see Merchants::Llm::Prompt#messages).
  def self.rows(messages)
    messages.last.fetch(:content).lines.drop(1).map { |line| JSON.parse(line) }
  end
end
