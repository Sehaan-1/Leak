# The only supported way to write to the ledger.
#
#   Ledger.post!(
#     household: h, occurred_on: Date.new(2026, 11, 3), memo: "NETFLIX",
#     lines: [ [ netflix_expense, 649_00 ], [ sbi_savings, -649_00 ] ]
#   )
#
# Amounts are Integer paise (see Paise). Positive = debit, negative = credit.
module Ledger
  class Error < StandardError; end
  class InvalidEntry < Error; end

  module_function

  def post!(household:, occurred_on:, memo:, lines:)
    lines = lines.map { |account, amount| [ account, amount ] }
    validate!(household, lines)

    JournalEntry.transaction do
      entry = household.journal_entries.create!(occurred_on: occurred_on, memo: memo)
      now = Time.current
      Posting.insert_all!(lines.map { |account, amount|
        { household_id: household.id, journal_entry_id: entry.id,
          account_id: account.id, amount_paise: amount, created_at: now }
      })
      entry
    end
  end

  def validate!(household, lines)
    raise InvalidEntry, "an entry needs at least two postings" if lines.size < 2

    lines.each do |account, amount|
      unless amount.is_a?(Integer) && !amount.zero?
        raise InvalidEntry, "amounts must be non-zero Integer paise, got #{amount.inspect}"
      end
      unless account.is_a?(Account) && account.household_id == household.id
        raise InvalidEntry, "every account must belong to household #{household.id}"
      end
    end

    total = lines.sum { |_, amount| amount }
    raise InvalidEntry, "postings must sum to zero, off by #{Paise.format(total)}" unless total.zero?
  end
end
