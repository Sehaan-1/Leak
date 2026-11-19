# One statement line in the ledger. The narration and reference can carry
# names, phone numbers and UPI handles, so they are encrypted at rest.
class BankTransaction < ApplicationRecord
  belongs_to :household
  belongs_to :bank_account
  belongs_to :statement_import
  belongs_to :journal_entry

  encrypts :narration
  encrypts :ref

  validates :narration, presence: true
  validates :amount_paise, numericality: { only_integer: true, other_than: 0 }
end
