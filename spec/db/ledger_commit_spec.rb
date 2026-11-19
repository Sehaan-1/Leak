require "rails_helper"

# The rest of the suite forces deferred checks with SET CONSTRAINTS inside a
# rolled-back transaction. This spec really commits, to prove the trigger
# fires at COMMIT time as designed.
RSpec.describe "Ledger balance check at COMMIT" do
  self.use_transactional_tests = false

  after do
    ActiveRecord::Base.connection.execute("TRUNCATE households, users, sessions RESTART IDENTITY CASCADE")
  end

  it "rolls back the whole transaction when an entry is unbalanced at commit" do
    household = Household.create!(name: "Commit test")
    bank = household.accounts.create!(name: "SBI Savings", kind: "asset")
    netflix = household.accounts.create!(name: "Netflix", kind: "expense")

    expect {
      ActiveRecord::Base.transaction do
        entry = household.journal_entries.create!(occurred_on: Date.new(2026, 11, 1), memo: "NETFLIX")
        Posting.insert_all!([
          { household_id: household.id, journal_entry_id: entry.id, account_id: netflix.id, amount_paise: 649_00, created_at: Time.current },
          { household_id: household.id, journal_entry_id: entry.id, account_id: bank.id, amount_paise: -600_00, created_at: Time.current }
        ])
      end
    }.to raise_error(ActiveRecord::StatementInvalid, /unbalanced/)

    expect(JournalEntry.count).to eq(0)
    expect(Posting.count).to eq(0)
  end

  it "commits a balanced entry built across several statements" do
    household = Household.create!(name: "Commit test")
    bank = household.accounts.create!(name: "SBI Savings", kind: "asset")
    netflix = household.accounts.create!(name: "Netflix", kind: "expense")

    Ledger.post!(household: household, occurred_on: Date.new(2026, 11, 1), memo: "NETFLIX",
      lines: [ [ netflix, 649_00 ], [ bank, -649_00 ] ])

    expect(Posting.sum(:amount_paise)).to eq(0)
    expect(bank.balance_paise).to eq(-649_00)
  end
end
