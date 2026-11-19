class StatementImport < ApplicationRecord
  belongs_to :household
  belongs_to :bank_account, optional: true
  has_many :bank_transactions, dependent: :destroy

  enum :status, { imported: "imported", rejected: "rejected" }, validate: true

  validates :filename, :file_sha256, presence: true
end
