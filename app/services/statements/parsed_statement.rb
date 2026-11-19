module Statements
  ParsedStatement = Data.define(:bank, :account_number, :ifsc, :period_from, :period_to,
                                :statement_date, :closing_balance_paise, :rows) do
    def account_last4
      account_number[-4..]
    end
  end
end
