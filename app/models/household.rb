class Household < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :accounts, dependent: :delete_all
  has_many :journal_entries, dependent: :delete_all
  has_many :bank_accounts, dependent: :delete_all
  has_many :statement_imports, dependent: :delete_all
  has_many :bank_transactions, dependent: :delete_all

  validates :name, presence: true

  # Every household gets exactly one suspense account for postings whose
  # counterparty is not yet known. Enforced by a partial unique index.
  def suspense_account
    accounts.find_or_create_by!(kind: "suspense") { |a| a.name = "Suspense" }
  end

  def opening_balances_account
    accounts.find_or_create_by!(name: "Opening balances", kind: "equity")
  end
end
