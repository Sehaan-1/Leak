module LedgerHelpers
  def create_household(name: "Test household")
    Household.create!(name: name)
  end

  def create_account(household, name:, kind:)
    household.accounts.create!(name: name, kind: kind)
  end

  # Deferred constraint triggers only fire at COMMIT, and transactional specs
  # never commit. This forces every pending deferred check to run now, inside
  # the spec's transaction, exactly as it would at COMMIT.
  def check_deferred_constraints!
    ActiveRecord::Base.connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
  ensure
    # Restore deferral for the rest of the spec if the check didn't raise.
    begin
      ActiveRecord::Base.connection.execute("SET CONSTRAINTS ALL DEFERRED")
    rescue ActiveRecord::StatementInvalid
      nil # transaction already aborted by the failed check
    end
  end

  # Raw SQL bypasses every Ruby-side validation, proving the database alone
  # enforces the invariant.
  def raw_insert_entry(household, occurred_on: "2026-11-01", memo: "raw")
    ActiveRecord::Base.connection.select_value(<<~SQL)
      INSERT INTO journal_entries (household_id, occurred_on, memo, created_at, updated_at)
      VALUES (#{Integer(household.id)}, '#{occurred_on}', '#{memo}', now(), now())
      RETURNING id
    SQL
  end

  def raw_insert_posting(household_id:, entry_id:, account_id:, amount_paise:)
    ActiveRecord::Base.connection.execute(<<~SQL)
      INSERT INTO postings (household_id, journal_entry_id, account_id, amount_paise, created_at)
      VALUES (#{Integer(household_id)}, #{Integer(entry_id)}, #{Integer(account_id)}, #{Integer(amount_paise)}, now())
    SQL
  end
end
