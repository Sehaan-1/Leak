# Double-entry ledger in integer paise.
#
# Invariants enforced by PostgreSQL itself, so no code path (console, raw SQL,
# a future importer bug) can break them:
#
#   1. Every journal entry's postings sum to exactly zero, checked at COMMIT by
#      a deferred constraint trigger (an entry is built across several INSERTs).
#   2. Every journal entry has at least two postings (no empty entries).
#   3. A posting can only reference an account and an entry of its own
#      household (composite foreign keys).
#   4. Amounts are non-zero bigint paise. No floats, no decimals.
#   5. Postings are append-only. Corrections are reversing entries.
#
# Sign convention: positive = debit, negative = credit.
class CreateLedger < ActiveRecord::Migration[8.1]
  def up
    create_table :households do |t|
      t.string :name, null: false
      t.timestamps
    end

    add_reference :users, :household, null: false, foreign_key: { on_delete: :cascade }

    create_enum :account_kind, %w[ asset liability equity income expense suspense ]

    create_table :accounts do |t|
      t.references :household, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.enum :kind, enum_type: :account_kind, null: false
      t.timestamps
    end
    add_index :accounts, %i[ household_id name ], unique: true
    add_index :accounts, %i[ id household_id ], unique: true
    add_index :accounts, :household_id, unique: true, where: "kind = 'suspense'",
      name: "index_accounts_one_suspense_per_household"

    create_table :journal_entries do |t|
      t.references :household, null: false, foreign_key: { on_delete: :cascade }
      t.date :occurred_on, null: false
      t.string :memo, null: false
      t.timestamps
    end
    add_index :journal_entries, %i[ id household_id ], unique: true
    add_index :journal_entries, %i[ household_id occurred_on ]

    create_table :postings do |t|
      t.bigint :household_id, null: false
      t.bigint :journal_entry_id, null: false
      t.bigint :account_id, null: false
      t.bigint :amount_paise, null: false
      t.datetime :created_at, null: false
    end
    add_index :postings, :journal_entry_id
    add_index :postings, :account_id
    add_check_constraint :postings, "amount_paise <> 0", name: "postings_amount_nonzero"

    execute <<~SQL
      ALTER TABLE postings
        ADD CONSTRAINT fk_postings_household
          FOREIGN KEY (household_id) REFERENCES households (id) ON DELETE CASCADE,
        ADD CONSTRAINT fk_postings_entry_same_household
          FOREIGN KEY (journal_entry_id, household_id)
          REFERENCES journal_entries (id, household_id) ON DELETE CASCADE,
        ADD CONSTRAINT fk_postings_account_same_household
          FOREIGN KEY (account_id, household_id)
          REFERENCES accounts (id, household_id);
    SQL

    execute <<~SQL
      CREATE FUNCTION ledger_assert_entry_balanced() RETURNS trigger
      LANGUAGE plpgsql AS $$
      DECLARE
        entry_ids bigint[] := ARRAY[]::bigint[];
        eid bigint;
        posting_count integer;
        total numeric;
      BEGIN
        IF TG_OP IN ('INSERT', 'UPDATE') THEN
          entry_ids := array_append(entry_ids, NEW.journal_entry_id);
        END IF;
        IF TG_OP IN ('UPDATE', 'DELETE') THEN
          entry_ids := array_append(entry_ids, OLD.journal_entry_id);
        END IF;

        FOREACH eid IN ARRAY entry_ids LOOP
          SELECT count(*), coalesce(sum(amount_paise), 0)
            INTO posting_count, total
            FROM postings WHERE journal_entry_id = eid;

          IF posting_count = 0 THEN
            -- Fine if the entry itself is gone (e.g. household deletion cascade).
            IF EXISTS (SELECT 1 FROM journal_entries WHERE id = eid) THEN
              RAISE EXCEPTION 'journal entry % has no postings', eid
                USING ERRCODE = 'check_violation', CONSTRAINT = 'journal_entry_has_postings';
            END IF;
          ELSIF total <> 0 THEN
            RAISE EXCEPTION 'journal entry % is unbalanced: postings sum to % paise', eid, total
              USING ERRCODE = 'check_violation', CONSTRAINT = 'journal_entry_balanced';
          END IF;
        END LOOP;

        RETURN NULL;
      END;
      $$;

      CREATE CONSTRAINT TRIGGER postings_balanced
        AFTER INSERT OR UPDATE OR DELETE ON postings
        DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW EXECUTE FUNCTION ledger_assert_entry_balanced();

      CREATE FUNCTION ledger_assert_entry_has_postings() RETURNS trigger
      LANGUAGE plpgsql AS $$
      BEGIN
        IF EXISTS (SELECT 1 FROM journal_entries WHERE id = NEW.id)
           AND NOT EXISTS (SELECT 1 FROM postings WHERE journal_entry_id = NEW.id) THEN
          RAISE EXCEPTION 'journal entry % has no postings', NEW.id
            USING ERRCODE = 'check_violation', CONSTRAINT = 'journal_entry_has_postings';
        END IF;
        RETURN NULL;
      END;
      $$;

      CREATE CONSTRAINT TRIGGER journal_entries_have_postings
        AFTER INSERT ON journal_entries
        DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW EXECUTE FUNCTION ledger_assert_entry_has_postings();

      CREATE FUNCTION ledger_forbid_posting_update() RETURNS trigger
      LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'postings are append-only; post a reversing entry instead'
          USING ERRCODE = 'restrict_violation';
      END;
      $$;

      CREATE TRIGGER postings_append_only
        BEFORE UPDATE ON postings
        FOR EACH ROW EXECUTE FUNCTION ledger_forbid_posting_update();
    SQL
  end

  def down
    drop_table :postings
    execute "DROP FUNCTION ledger_assert_entry_balanced(); DROP FUNCTION ledger_forbid_posting_update();"
    drop_table :journal_entries
    execute "DROP FUNCTION ledger_assert_entry_has_postings();"
    drop_table :accounts
    drop_enum :account_kind
    remove_reference :users, :household
    drop_table :households
  end
end
