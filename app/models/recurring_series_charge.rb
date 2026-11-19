# A ledger row's place in a recurring series. A row is in at most one.
class RecurringSeriesCharge < ApplicationRecord
  belongs_to :recurring_series
  belongs_to :bank_transaction
end
