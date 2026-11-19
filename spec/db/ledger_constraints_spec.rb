require "rails_helper"

# These specs go around the models with raw SQL on purpose: the database must
# hold the ledger invariants even if application code is wrong.
RSpec.describe "Ledger database constraints" do
  let(:household) { create_household }
  let(:bank) { create_account(household, name: "SBI Savings", kind: "asset") }
  let(:netflix) { create_account(household, name: "Netflix", kind: "expense") }

  def rejection(constraint)
    raise_error(ActiveRecord::StatementInvalid, /#{constraint}|unbalanced|no postings/)
  end

  it "accepts a balanced entry" do
    entry_id = raw_insert_entry(household)
    raw_insert_posting(household_id: household.id, entry_id: entry_id, account_id: netflix.id, amount_paise: 649_00)
    raw_insert_posting(household_id: household.id, entry_id: entry_id, account_id: bank.id, amount_paise: -649_00)

    expect { check_deferred_constraints! }.not_to raise_error
  end

  it "accepts an entry with more than two postings that nets to zero" do
    entry_id = raw_insert_entry(household)
    raw_insert_posting(household_id: household.id, entry_id: entry_id, account_id: netflix.id, amount_paise: 600_00)
    raw_insert_posting(household_id: household.id, entry_id: entry_id, account_id: household.suspense_account.id, amount_paise: 49_00)
    raw_insert_posting(household_id: household.id, entry_id: entry_id, account_id: bank.id, amount_paise: -649_00)

    expect { check_deferred_constraints! }.not_to raise_error
  end

  it "rejects an unbalanced entry, even off by one paisa" do
    entry_id = raw_insert_entry(household)
    raw_insert_posting(household_id: household.id, entry_id: entry_id, account_id: netflix.id, amount_paise: 649_00)
    raw_insert_posting(household_id: household.id, entry_id: entry_id, account_id: bank.id, amount_paise: -648_99)

    expect { check_deferred_constraints! }.to rejection("journal_entry_balanced")
  end

  it "rejects an entry with a single posting" do
    entry_id = raw_insert_entry(household)
    raw_insert_posting(household_id: household.id, entry_id: entry_id, account_id: netflix.id, amount_paise: 649_00)

    expect { check_deferred_constraints! }.to rejection("journal_entry_balanced")
  end

  it "rejects an entry with no postings" do
    raw_insert_entry(household)

    expect { check_deferred_constraints! }.to rejection("journal_entry_has_postings")
  end

  it "rejects deleting one leg of a committed entry" do
    entry = Ledger.post!(household: household, occurred_on: Date.new(2026, 11, 1), memo: "NETFLIX",
      lines: [ [ netflix, 649_00 ], [ bank, -649_00 ] ])
    check_deferred_constraints!

    ActiveRecord::Base.connection.execute(
      "DELETE FROM postings WHERE journal_entry_id = #{entry.id} AND account_id = #{bank.id}"
    )
    expect { check_deferred_constraints! }.to rejection("journal_entry_balanced")
  end

  it "rejects zero-amount postings immediately" do
    entry_id = raw_insert_entry(household)
    expect {
      raw_insert_posting(household_id: household.id, entry_id: entry_id, account_id: netflix.id, amount_paise: 0)
    }.to raise_error(ActiveRecord::StatementInvalid, /postings_amount_nonzero/)
  end

  it "rejects updates to postings (append-only)" do
    entry = Ledger.post!(household: household, occurred_on: Date.new(2026, 11, 1), memo: "NETFLIX",
      lines: [ [ netflix, 649_00 ], [ bank, -649_00 ] ])

    expect {
      ActiveRecord::Base.connection.execute(
        "UPDATE postings SET amount_paise = amount_paise * 2 WHERE journal_entry_id = #{entry.id}"
      )
    }.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
  end

  it "rejects a posting to another household's account" do
    other = create_household(name: "Other household")
    other_account = create_account(other, name: "Their bank", kind: "asset")
    entry_id = raw_insert_entry(household)

    expect {
      raw_insert_posting(household_id: household.id, entry_id: entry_id, account_id: other_account.id, amount_paise: 1)
    }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_postings_account_same_household/)
  end

  it "rejects a posting that claims another household to reach its account" do
    other = create_household(name: "Other household")
    other_account = create_account(other, name: "Their bank", kind: "asset")
    entry_id = raw_insert_entry(household)

    expect {
      raw_insert_posting(household_id: other.id, entry_id: entry_id, account_id: other_account.id, amount_paise: 1)
    }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_postings_entry_same_household/)
  end

  it "allows only one suspense account per household" do
    household.suspense_account
    expect {
      Account.insert!({ household_id: household.id, name: "Suspense 2", kind: "suspense" })
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "rejects unknown account kinds" do
    expect {
      Account.insert!({ household_id: household.id, name: "Mystery", kind: "vibes" })
    }.to raise_error(ActiveRecord::StatementInvalid, /invalid input value for enum account_kind/)
  end

  it "deletes a household's whole ledger cleanly (delete-my-data path)" do
    Ledger.post!(household: household, occurred_on: Date.new(2026, 11, 1), memo: "NETFLIX",
      lines: [ [ netflix, 649_00 ], [ bank, -649_00 ] ])
    check_deferred_constraints!

    ActiveRecord::Base.connection.execute("DELETE FROM households WHERE id = #{household.id}")

    expect { check_deferred_constraints! }.not_to raise_error
    expect(Posting.where(household_id: household.id)).to be_empty
    expect(Account.where(household_id: household.id)).to be_empty
  end
end
