# Slice 7: the review queue and dismissed findings.
#
# - resolution "manual": the household picked the counterparty in the review
#   queue. Picking a merchant also learns a household MerchantAlias, so the
#   rules resolve that payee from then on.
# - finding_dismissals: findings the household has marked as fine. Detection
#   replaces series and findings on every run (ADR 0009), so a dismissal
#   can't point at a finding. It points at a ledger row instead, which never
#   changes: the first charge at the new price for a price increase, or the
#   first charge of the series otherwise. A finding is dismissed while its
#   evidence still contains that row (Finding#dismissed_by?).
class AddReviewAndDismissals < ActiveRecord::Migration[8.1]
  def up
    add_enum_value :resolution_method, "manual", before: "abstained"

    create_table :finding_dismissals do |t|
      t.references :household, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.enum :kind, enum_type: :finding_kind, null: false
      t.bigint :bank_transaction_id, null: false
      t.timestamps
    end
    add_index :finding_dismissals, %i[ household_id kind bank_transaction_id ], unique: true,
      name: "index_finding_dismissals_unique"
    add_index :finding_dismissals, :bank_transaction_id
    add_foreign_key :finding_dismissals, :bank_transactions, column: %i[ bank_transaction_id household_id ],
      primary_key: %i[ id household_id ], on_delete: :cascade, name: "fk_finding_dismissals_transaction_same_household"
  end

  def down
    drop_table :finding_dismissals
    # PostgreSQL can't drop an enum value; "manual" stays in resolution_method.
  end
end
