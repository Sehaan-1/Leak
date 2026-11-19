# A finding the household has marked as fine. Findings are rebuilt on every
# detection run, so a dismissal is keyed on a ledger row instead: the
# finding's anchor (Finding#anchor_transaction_id). A rebuilt finding is
# still dismissed while its evidence contains that row, so a later
# statement that extends the series doesn't bring it back, but a new price
# increase (a new first charge at the new price) does.
class FindingDismissal < ApplicationRecord
  belongs_to :household
  belongs_to :bank_transaction

  enum :kind, %w[ subscription price_increase duplicate ].index_with(&:itself), prefix: :kind, validate: true

  # Ids of the given findings that the household has dismissed. Preload
  # recurring_series: :series_charges.
  def self.dismissed_ids(household, findings)
    keys = household.finding_dismissals.pluck(:kind, :bank_transaction_id).to_set
    return Set.new if keys.empty?

    findings.select { |finding| finding.evidence_transaction_ids.any? { |id| keys.include?([ finding.kind, id ]) } }
      .to_set(&:id)
  end
end
