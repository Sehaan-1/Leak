module Statements
  # One transaction line of a statement. Amounts are Integer paise.
  Row = Data.define(:line_no, :value_on, :posted_on, :narration, :ref,
                    :debit_paise, :credit_paise, :balance_paise) do
    # Signed movement on the bank account: credits positive, debits negative.
    def amount_paise
      credit_paise - debit_paise
    end

    def summary
      "#{posted_on.strftime("%d/%m/%Y")} #{narration.truncate(40)}"
    end
  end
end
