# Append-only: the database rejects UPDATEs. Correct mistakes with a
# reversing entry. Sign convention: positive = debit, negative = credit.
class Posting < ApplicationRecord
  belongs_to :household
  belongs_to :journal_entry
  belongs_to :account

  validates :amount_paise, numericality: { only_integer: true, other_than: 0 }

  def readonly?
    persisted? || super
  end
end
