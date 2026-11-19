# Bank statement intake: PDF -> text -> parsed rows -> reconciliation -> ledger.
#
# Amounts, dates and balances come from a per-bank parser and must reconcile
# exactly; nothing here guesses. Any doubt rejects the statement with the line
# that caused it.
module Statements
  class Error < StandardError
    attr_reader :line_no

    def initialize(message, line_no: nil)
      super(message)
      @line_no = line_no
    end
  end

  class UnsupportedFormat < Error; end
  class PasswordRequired < Error; end
  class NoTextLayer < Error; end
  class ExtractionFailed < Error; end
  class ParseError < Error; end
  class DoesNotTie < Error; end
  class Conflict < Error; end

  PARSERS = [ "Statements::Parsers::Sbi" ].freeze

  def self.parser_for(text)
    PARSERS.map(&:constantize).find { |parser| parser.matches?(text) } ||
      raise(UnsupportedFormat, "This doesn't look like a supported bank statement (supported: SBI).")
  end
end
