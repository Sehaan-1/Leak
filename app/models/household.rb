class Household < ApplicationRecord
  # Deleting a household (destroy) or its data (erase_data!) goes in this
  # order, because the ledger's foreign keys don't all cascade: postings and
  # bank accounts point at accounts with no ON DELETE, so accounts go last.
  # Deleting journal entries cascades to their postings and bank transactions,
  # and those to series charges, findings' evidence and dismissals.
  has_many :users, dependent: :destroy
  has_many :finding_dismissals, dependent: :delete_all
  has_many :findings, dependent: :delete_all
  has_many :recurring_series, class_name: "RecurringSeries", dependent: :delete_all
  has_many :journal_entries, dependent: :delete_all
  has_many :bank_transactions, dependent: :delete_all
  has_many :statement_imports, dependent: :delete_all
  has_many :bank_accounts, dependent: :delete_all
  has_many :accounts, dependent: :delete_all
  # Learnt in the review queue. The global catalogue aliases have no household.
  has_many :merchant_aliases, dependent: :delete_all

  validates :name, presence: true

  scope :demo, -> { where.not(demo_expires_at: nil) }
  scope :expired_demo, ->(now = Time.current) { where(demo_expires_at: ..now) }

  def demo? = demo_expires_at.present?

  # Every household gets exactly one suspense account for postings whose
  # counterparty is not yet known. Enforced by a partial unique index.
  def suspense_account
    accounts.find_or_create_by!(kind: "suspense") { |a| a.name = "Suspense" }
  end

  def opening_balances_account
    accounts.find_or_create_by!(name: "Opening balances", kind: "equity")
  end

  # What Leak holds for this household, as shown on the "Your data" screen.
  def data_counts
    {
      statements: statement_imports.imported.count,
      transactions: bank_transactions.count,
      subscriptions: findings.kind_subscription.count,
      learned_merchants: merchant_aliases.count,
      dismissed_findings: finding_dismissals.count
    }
  end

  # "Delete my data": everything imported, detected or learnt, in one
  # transaction. The household and its users stay, so they can sign in and
  # start again. Returns the counts that were deleted.
  def erase_data!
    transaction do
      counts = data_counts
      finding_dismissals.delete_all
      findings.delete_all
      recurring_series.delete_all
      journal_entries.delete_all
      bank_transactions.delete_all
      statement_imports.delete_all
      bank_accounts.delete_all
      accounts.delete_all
      merchant_aliases.delete_all
      counts
    end
  end
end
