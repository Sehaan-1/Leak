# Statement intake: bank accounts, one row per uploaded statement (imported or
# rejected), and one row per statement line that made it into the ledger.
#
# Idempotency lives in the database:
#   - a bank transaction's fingerprint is unique per household, so the same
#     statement line can never be posted twice (re-uploads, overlaps);
#   - a successfully imported file (by SHA-256) is unique per household.
class CreateStatementImports < ActiveRecord::Migration[8.1]
  def change
    create_enum :bank_code, %w[ sbi ]
    create_enum :statement_import_status, %w[ imported rejected ]

    create_table :bank_accounts do |t|
      t.references :household, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :account_id, null: false
      t.enum :bank, enum_type: :bank_code, null: false
      t.string :number_last4, null: false, limit: 4
      # HMAC of bank + IFSC + full account number: matches statements to the
      # account without storing the number itself.
      t.string :number_digest, null: false
      t.bigint :opening_entry_id
      t.timestamps
    end
    add_index :bank_accounts, %i[ household_id number_digest ], unique: true
    add_index :bank_accounts, :account_id, unique: true
    add_index :bank_accounts, %i[ id household_id ], unique: true
    add_foreign_key :bank_accounts, :accounts, column: %i[ account_id household_id ],
      primary_key: %i[ id household_id ], name: "fk_bank_accounts_ledger_account_same_household"
    add_foreign_key :bank_accounts, :journal_entries, column: :opening_entry_id, on_delete: :nullify

    create_table :statement_imports do |t|
      t.references :household, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :bank_account_id
      t.enum :status, enum_type: :statement_import_status, null: false
      t.string :filename, null: false
      t.string :file_sha256, null: false, limit: 64
      t.date :period_from
      t.date :period_to
      t.bigint :opening_balance_paise
      t.bigint :closing_balance_paise
      t.integer :rows_count, null: false, default: 0
      t.integer :new_rows_count, null: false, default: 0
      t.text :error_message
      t.integer :error_line
      t.timestamps
    end
    add_index :statement_imports, %i[ household_id file_sha256 ], unique: true,
      where: "status = 'imported'", name: "index_statement_imports_one_import_per_file"
    add_index :statement_imports, :bank_account_id
    add_foreign_key :statement_imports, :bank_accounts, column: %i[ bank_account_id household_id ],
      primary_key: %i[ id household_id ], on_delete: :cascade,
      name: "fk_statement_imports_bank_account_same_household"
    add_check_constraint :statement_imports, <<~SQL.squish, name: "statement_imports_imported_complete"
      status <> 'imported' OR (
        bank_account_id IS NOT NULL AND period_from IS NOT NULL AND period_to IS NOT NULL
        AND opening_balance_paise IS NOT NULL AND closing_balance_paise IS NOT NULL
        AND period_from <= period_to AND rows_count > 0
      )
    SQL
    add_check_constraint :statement_imports, "status <> 'rejected' OR error_message IS NOT NULL",
      name: "statement_imports_rejected_has_reason"

    create_table :bank_transactions do |t|
      t.references :household, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :bank_account_id, null: false
      t.references :statement_import, null: false, foreign_key: { on_delete: :cascade }
      t.references :journal_entry, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.date :posted_on, null: false
      t.date :value_on, null: false
      t.text :narration, null: false # Active Record Encryption ciphertext
      t.text :ref                     # Active Record Encryption ciphertext
      t.bigint :amount_paise, null: false
      t.bigint :balance_after_paise, null: false
      t.string :fingerprint, null: false, limit: 64
      t.integer :position, null: false
      t.timestamps
    end
    add_index :bank_transactions, %i[ household_id fingerprint ], unique: true
    add_index :bank_transactions, %i[ bank_account_id posted_on ]
    add_foreign_key :bank_transactions, :bank_accounts, column: %i[ bank_account_id household_id ],
      primary_key: %i[ id household_id ], on_delete: :cascade,
      name: "fk_bank_transactions_bank_account_same_household"
    add_check_constraint :bank_transactions, "amount_paise <> 0", name: "bank_transactions_amount_nonzero"
  end
end
