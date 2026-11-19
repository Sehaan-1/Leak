# Charges at one merchant repeating on a cadence (Detection::Engine). The
# charges are ordered ledger rows; `level` on each numbers the price levels
# when the price stepped. Replaced on every detection run.
class RecurringSeries < ApplicationRecord
  self.table_name = "recurring_series"

  belongs_to :household
  belongs_to :merchant
  has_many :series_charges, -> { order(:level, :id) }, class_name: "RecurringSeriesCharge", inverse_of: :recurring_series
  has_many :bank_transactions, through: :series_charges
  has_many :findings, inverse_of: :recurring_series

  enum :cadence, %w[ weekly monthly quarterly half_yearly annual ].index_with(&:itself), prefix: :cadence, validate: true
  enum :status, %w[ active ended ].index_with(&:itself), prefix: :status, validate: true

  scope :flagged, -> { where(flagged: true) }
  scope :commitments, -> { where(flagged: false) }
end
