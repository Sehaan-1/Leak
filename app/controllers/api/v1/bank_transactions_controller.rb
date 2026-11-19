module Api
  module V1
    # Statement lines in the ledger, newest first. Narrations are decrypted
    # only here, for the signed-in household.
    class BankTransactionsController < BaseController
      PER_PAGE = 100

      def index
        page = [ params.fetch(:page, 1).to_i, 1 ].max
        rows = current_household.bank_transactions
          .includes(bank_account: :account)
          .order(posted_on: :desc, statement_import_id: :desc, position: :desc)
          .offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a

        render json: {
          bank_transactions: rows.first(PER_PAGE).map { |row| self.class.payload(row) },
          next_page: rows.size > PER_PAGE ? page + 1 : nil
        }
      end

      def self.payload(row)
        {
          id: row.id,
          posted_on: row.posted_on.iso8601,
          value_on: row.value_on.iso8601,
          narration: row.narration,
          ref: row.ref,
          amount_paise: row.amount_paise,
          balance_after_paise: row.balance_after_paise,
          bank_account: { id: row.bank_account.id, name: row.bank_account.display_name }
        }
      end
    end
  end
end
