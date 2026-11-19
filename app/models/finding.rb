# Something detection flags for the household, traced to its evidence: the
# series and its charges, plus the first charge at the new price for a
# price increase, or the other series for a duplicate subscription.
class Finding < ApplicationRecord
  belongs_to :household
  belongs_to :recurring_series
  belongs_to :related_series, class_name: "RecurringSeries", optional: true
  belongs_to :step_transaction, class_name: "BankTransaction", optional: true

  enum :kind, %w[ subscription price_increase duplicate ].index_with(&:itself), prefix: :kind, validate: true

  # Ledger rows that identify this finding across detection runs (see
  # FindingDismissal): the first charge at the new price for a price
  # increase, otherwise the series' charges.
  def evidence_transaction_ids
    kind_price_increase? ? [ step_transaction_id ] : recurring_series.series_charges.map(&:bank_transaction_id)
  end

  # The row a dismissal of this finding is keyed on.
  def anchor_transaction_id
    kind_price_increase? ? step_transaction_id : recurring_series.series_charges.first.bank_transaction_id
  end
end
