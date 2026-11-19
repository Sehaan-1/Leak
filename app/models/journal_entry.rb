# Create entries through Ledger.post!, which validates before the database
# does. The database is the backstop: see db/migrate/*_create_ledger.rb.
class JournalEntry < ApplicationRecord
  belongs_to :household
  has_many :postings, dependent: :delete_all

  validates :occurred_on, :memo, presence: true
end
