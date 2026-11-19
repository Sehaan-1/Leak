# Slice 6: recurring-charge detection (Detection::Engine, ADR 0009).
#
# A recurring series is a merchant's charges that repeat on a cadence; each
# charge belongs to at most one series, and `level` numbers its price
# levels (0, 1, ... after each price step). Findings are what the household
# is shown: an active subscription, a price increase or a second
# subscription at the same merchant. Each points at its series, and price
# increases at the first charge at the new price, so every finding traces
# to ledger rows. Detection replaces a household's series and findings on
# every run.
class CreateDetection < ActiveRecord::Migration[8.1]
  def change
    create_enum :series_cadence, %w[ weekly monthly quarterly half_yearly annual ]
    create_enum :series_status, %w[ active ended ]
    create_enum :finding_kind, %w[ subscription price_increase duplicate ]

    # Composite foreign keys below keep series, charges and findings inside
    # one household.
    add_index :bank_transactions, %i[ id household_id ], unique: true

    create_table :recurring_series do |t|
      t.references :household, null: false, foreign_key: { on_delete: :cascade }
      t.references :merchant, null: false, foreign_key: { on_delete: :restrict }
      t.enum :cadence, enum_type: :series_cadence, null: false
      t.enum :status, enum_type: :series_status, null: false
      # Leak categories are flagged; commitments (SIPs, EMIs, rent,
      # insurance, utilities, card bills) are kept as series but never
      # flagged.
      t.boolean :flagged, null: false
      t.bigint :amount_paise, null: false
      t.bigint :monthly_cost_paise, null: false
      t.date :first_charged_on, null: false
      t.date :last_charged_on, null: false
      t.date :next_expected_on, null: false
      t.integer :charges_count, null: false
      t.timestamps
    end
    add_index :recurring_series, %i[ id household_id ], unique: true
    add_check_constraint :recurring_series, "amount_paise > 0 AND monthly_cost_paise > 0", name: "recurring_series_amounts_positive"
    add_check_constraint :recurring_series, "first_charged_on <= last_charged_on AND last_charged_on < next_expected_on",
      name: "recurring_series_dates_ordered"
    add_check_constraint :recurring_series, "charges_count >= 2", name: "recurring_series_repeats"

    create_table :recurring_series_charges do |t|
      t.bigint :household_id, null: false
      t.bigint :recurring_series_id, null: false
      t.bigint :bank_transaction_id, null: false
      t.integer :level, null: false, default: 0
    end
    add_index :recurring_series_charges, :bank_transaction_id, unique: true
    add_index :recurring_series_charges, :recurring_series_id
    add_foreign_key :recurring_series_charges, :recurring_series, column: %i[ recurring_series_id household_id ],
      primary_key: %i[ id household_id ], on_delete: :cascade, name: "fk_series_charges_series_same_household"
    add_foreign_key :recurring_series_charges, :bank_transactions, column: %i[ bank_transaction_id household_id ],
      primary_key: %i[ id household_id ], on_delete: :cascade, name: "fk_series_charges_transaction_same_household"
    add_check_constraint :recurring_series_charges, "level >= 0", name: "recurring_series_charges_level_nonnegative"

    create_table :findings do |t|
      t.bigint :household_id, null: false
      t.bigint :recurring_series_id, null: false
      t.enum :kind, enum_type: :finding_kind, null: false
      t.bigint :amount_paise, null: false
      t.bigint :monthly_cost_paise, null: false
      # price_increase: the old price and the first charge at the new one.
      t.bigint :previous_amount_paise
      t.bigint :step_transaction_id
      # duplicate: the other subscription at the same merchant.
      t.bigint :related_series_id
      t.timestamps
    end
    add_index :findings, %i[ recurring_series_id kind ], unique: true
    add_index :findings, :household_id
    add_foreign_key :findings, :households, on_delete: :cascade
    add_foreign_key :findings, :recurring_series, column: %i[ recurring_series_id household_id ],
      primary_key: %i[ id household_id ], on_delete: :cascade, name: "fk_findings_series_same_household"
    add_foreign_key :findings, :recurring_series, column: %i[ related_series_id household_id ],
      primary_key: %i[ id household_id ], on_delete: :cascade, name: "fk_findings_related_series_same_household"
    add_foreign_key :findings, :bank_transactions, column: %i[ step_transaction_id household_id ],
      primary_key: %i[ id household_id ], on_delete: :cascade, name: "fk_findings_step_transaction_same_household"
    add_check_constraint :findings, <<~SQL.squish, name: "findings_kind_details"
      (kind = 'subscription' AND previous_amount_paise IS NULL AND step_transaction_id IS NULL AND related_series_id IS NULL)
      OR (kind = 'price_increase' AND previous_amount_paise IS NOT NULL AND step_transaction_id IS NOT NULL
          AND amount_paise > previous_amount_paise AND related_series_id IS NULL)
      OR (kind = 'duplicate' AND related_series_id IS NOT NULL AND related_series_id <> recurring_series_id
          AND previous_amount_paise IS NULL AND step_transaction_id IS NULL)
    SQL
  end
end
