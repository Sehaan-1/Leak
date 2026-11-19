# One statement line in the ledger. The narration and reference can carry
# names, phone numbers and UPI handles, so they are encrypted at rest.
class BankTransaction < ApplicationRecord
  belongs_to :household
  belongs_to :bank_account
  belongs_to :statement_import
  belongs_to :journal_entry
  belongs_to :merchant, optional: true

  enum :counterparty, { merchant: "merchant", person: "person", bank: "bank", cash: "cash" },
    prefix: :counterparty, validate: { allow_nil: true }
  enum :resolution, %w[ vpa_alias name_alias trigram rule llm abstained ].index_with(&:itself),
    prefix: :resolved_by, validate: { allow_nil: true }

  scope :needs_review, -> { where(resolution: "abstained") }

  encrypts :narration
  encrypts :ref
  encrypts :resolution_evidence

  validates :narration, presence: true
  validates :amount_paise, numericality: { only_integer: true, other_than: 0 }

  def apply_resolution(result)
    assign_attributes(merchant: result.merchant, counterparty: result.counterparty, resolution: result.via,
      resolution_evidence: result.evidence.to_s.first(500), resolution_model: result.model, resolved_at: Time.current)
  end
end
