module Statements
  # A statement is imported only if it ties exactly:
  #   - every row moves money one way (debit xor credit),
  #   - rows are in date order and inside the statement period,
  #   - each row's balance = previous balance + credit - debit,
  #   - the last balance matches the closing balance printed in the header
  #     (when the header balance is as of the period end).
  # The opening balance is derived from the first row, so a dropped first
  # row can't hide: the parser rejects any unreadable dated line.
  module Reconciler
    module_function

    # Returns the opening balance in paise, or raises DoesNotTie.
    def check!(statement)
      rows = statement.rows
      opening = rows.first.balance_paise - rows.first.amount_paise

      rows.each_with_index do |row, index|
        unless row.posted_on.between?(statement.period_from, statement.period_to)
          fail_row!(row, index, "is dated outside the statement period " \
            "(#{statement.period_from.strftime("%d/%m/%Y")}–#{statement.period_to.strftime("%d/%m/%Y")})")
        end
        next if index.zero?

        previous = rows[index - 1]
        if row.posted_on < previous.posted_on
          fail_row!(row, index, "is dated before the row above it")
        end

        expected = previous.balance_paise + row.amount_paise
        if row.balance_paise != expected
          fail_row!(row, index, "doesn't tie: the balance should be #{Paise.format(expected)} " \
            "but the statement shows #{Paise.format(row.balance_paise)} " \
            "(off by #{Paise.format(row.balance_paise - expected)})")
        end
      end

      check_closing!(statement)
      opening
    end

    def check_closing!(statement)
      closing = statement.closing_balance_paise
      return if closing.nil? || statement.statement_date.nil? || statement.statement_date != statement.period_to

      last = statement.rows.last
      return if last.balance_paise == closing

      raise DoesNotTie.new(
        "The last balance (#{Paise.format(last.balance_paise)}) doesn't match the statement's " \
        "closing balance (#{Paise.format(closing)}). A transaction may be missing.",
        line_no: last.line_no
      )
    end

    def fail_row!(row, index, problem)
      raise DoesNotTie.new("Row #{index + 1} (#{row.summary}) #{problem}.", line_no: row.line_no)
    end
  end
end
