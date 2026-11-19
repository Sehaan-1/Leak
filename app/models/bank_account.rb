# A real bank account, mirrored by one asset account in the ledger.
# Stores only the last four digits of the account number; statements are
# matched by an HMAC digest of the full number.
class BankAccount < ApplicationRecord
  BANK_NAMES = { "sbi" => "SBI" }.freeze

  belongs_to :household
  belongs_to :account
  belongs_to :opening_entry, class_name: "JournalEntry", optional: true
  has_many :statement_imports, dependent: :destroy
  has_many :bank_transactions, dependent: :destroy

  def self.for_statement!(household, statement)
    digest = Statements::Fingerprint.account_number_digest(statement.bank, statement.ifsc, statement.account_number)
    household.bank_accounts.find_by(number_digest: digest) || begin
      name = "#{BANK_NAMES.fetch(statement.bank)} ••#{statement.account_last4}"
      household.bank_accounts.create!(
        bank: statement.bank, number_last4: statement.account_last4, number_digest: digest,
        account: household.accounts.find_or_create_by!(name: name, kind: "asset")
      )
    end
  end

  def display_name
    account.name
  end

  # The opening balance is the one printed (derived) on the statement whose
  # period starts earliest. Kept as a single system-maintained journal entry
  # that is replaced when an earlier statement arrives, so the ledger ends up
  # identical whatever order statements are imported in.
  def sync_opening_balance!
    earliest = statement_imports.imported.order(:period_from, :id).first
    target = earliest&.opening_balance_paise.to_i
    date = earliest&.period_from

    current = opening_entry
    current_amount = current&.postings&.find_by(account_id: account_id)&.amount_paise.to_i
    return if current_amount == target && current&.occurred_on == date

    current&.destroy!
    entry = if target.zero?
      nil
    else
      Ledger.post!(household: household, occurred_on: date, memo: "Opening balance · #{display_name}",
        lines: [ [ account, target ], [ household.opening_balances_account, -target ] ])
    end
    update!(opening_entry: entry)
  end

  # Ledger balance of the bank account versus the closing balance of the
  # latest statement. Differs only if a statement is missing in between.
  def reconciliation
    latest = statement_imports.imported.order(:period_to, :id).last
    return nil unless latest

    ledger = account.balance_paise
    { ledger_balance_paise: ledger, statement_balance_paise: latest.closing_balance_paise,
      as_of: latest.period_to, difference_paise: ledger - latest.closing_balance_paise }
  end
end
