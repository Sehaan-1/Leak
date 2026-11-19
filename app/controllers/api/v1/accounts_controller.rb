module Api
  module V1
    class AccountsController < BaseController
      def index
        accounts = current_household.accounts.with_balances.order(:kind, :name)
        render json: {
          accounts: accounts.map { |a|
            { id: a.id, name: a.name, kind: a.kind, balance_paise: a.balance_paise }
          }
        }
      end
    end
  end
end
