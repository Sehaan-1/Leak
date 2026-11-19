require "rails_helper"

RSpec.describe Statements::Importer do
  let(:household) { create_household }

  def import_text(text, filename: "statement.pdf", into: household)
    described_class.import_text(household: into, text: text, filename: filename).tap { check_deferred_constraints! }
  end

  def ledger_snapshot(target = household)
    bank_account = target.bank_accounts.sole
    {
      transactions: target.bank_transactions.order(:posted_on, :balance_after_paise)
        .map { |t| [ t.posted_on, t.amount_paise, t.balance_after_paise, t.narration.delete(" ") ] },
      bank_balance: bank_account.account.balance_paise,
      suspense_balance: target.suspense_account.balance_paise,
      opening: [ bank_account.opening_entry&.occurred_on, bank_account.opening_entry&.postings&.find_by(account: bank_account.account)&.amount_paise ]
    }
  end

  context "with the fabricated SBI sample" do
    it "posts every row to the ledger and ties to the closing balance" do
      import = import_text(sample_text)

      expect(import).to be_imported
      expect(import).to have_attributes(rows_count: 7, new_rows_count: 7, opening_balance_paise: 12_450_25,
        closing_balance_paise: 24_850_75, period_from: Date.new(2026, 11, 1), period_to: Date.new(2026, 11, 19))
      bank_account = import.bank_account
      expect(bank_account).to have_attributes(bank: "sbi", number_last4: "9475", display_name: "SBI ••9475")
      expect(bank_account.account.balance_paise).to eq(24_850_75)
      expect(bank_account.reconciliation).to include(difference_paise: 0)
      expect(household.suspense_account.balance_paise).to eq(-(24_850_75 - 12_450_25))
      expect(household.opening_balances_account.balance_paise).to eq(-12_450_25)
      expect(Posting.where(household: household).sum(:amount_paise)).to eq(0)
    end

    it "never stores the full account number" do
      import_text(sample_text)
      dump = BankAccount.connection.select_all("SELECT * FROM bank_accounts").to_a.to_s
      expect(dump).not_to include("39481029475")
    end

    it "encrypts narrations at rest" do
      import_text(sample_text)
      raw = BankTransaction.connection.select_values("SELECT narration FROM bank_transactions")
      expect(raw.join).not_to include("ANANYA")
      expect(household.bank_transactions.map(&:narration).join).to include("ANANYA")
    end

    it "is idempotent: importing the same file twice changes nothing" do
      first = import_text(sample_text)
      before = ledger_snapshot
      expect { expect(import_text(sample_text)).to eq(first) }.not_to change { [ JournalEntry.count, StatementImport.count ] }
      expect(ledger_snapshot).to eq(before)
    end

    it "skips rows already in the ledger when a different file has the same rows" do
      import_text(sample_text)
      before = ledger_snapshot
      redownloaded = sample_text.sub("Monthly Avg Balance : 18,420.50", "Monthly Avg Balance : 18,421.00")
      second = import_text(redownloaded, filename: "again.pdf")

      expect(second).to have_attributes(status: "imported", rows_count: 7, new_rows_count: 0)
      expect(ledger_snapshot).to eq(before)
    end

    it "writes nothing and records the reason when a statement doesn't tie" do
      import = import_text(sample_text.sub("25,524.75", "25,542.75"), filename: "bad.pdf")

      expect(import).to be_rejected
      expect(import.error_message).to match(/Row 3 .* doesn't tie/)
      expect(import.error_line).to be_a(Integer)
      expect(household.bank_transactions).to be_empty
      expect(JournalEntry.where(household: household)).to be_empty
    end

    it "rejects things that aren't SBI statements" do
      import = import_text("Some other bank\nDate Narration Amount\n")
      expect(import).to be_rejected
      expect(import.error_message).to match(/supported bank statement/)
    end
  end

  # Ledger property tests on synthetic histories. Seeded from RSpec's --seed.
  describe "properties" do
    let(:rng) { Random.new(RSpec.configuration.seed) }
    let(:opening) { 37_512_40 }
    let(:history) { SyntheticSbi.history(rng, from: Date.new(2026, 8, 1), to: Date.new(2026, 10, 31), per_day: 0..3) }

    def statement(from, to, **options)
      SyntheticSbi.statement_for(history, from: from, to: to, opening_paise: opening, **options)
    end

    it "imports overlapping statements to the same ledger in either order" do
      a = statement(Date.new(2026, 8, 1), Date.new(2026, 9, 20))
      b = statement(Date.new(2026, 9, 5), Date.new(2026, 10, 31))
      c = statement(Date.new(2026, 8, 15), Date.new(2026, 10, 10))

      snapshots = [ [ a, b, c ], [ c, b, a ], [ b, a, c ] ].map.with_index do |order, index|
        target = create_household(name: "Order #{index}")
        order.each { |text| expect(import_text(text, into: target)).to be_imported }
        ledger_snapshot(target)
      end

      expect(snapshots.uniq.size).to eq(1)
      expected_rows = history.map { |t| [ t.posted_on, t.amount_paise ] }.sort
      expect(snapshots.first[:transactions].map { |t| t.first(2) }.sort).to eq(expected_rows)
      expect(snapshots.first[:bank_balance]).to eq(opening + history.sum(&:amount_paise))
      expect(snapshots.first[:opening]).to eq([ Date.new(2026, 8, 1), opening ])
    end

    it "keeps every entry balanced and the bank account equal to the latest closing balance" do
      [ statement(Date.new(2026, 9, 1), Date.new(2026, 9, 30)),
        statement(Date.new(2026, 8, 1), Date.new(2026, 8, 31)),
        statement(Date.new(2026, 10, 1), Date.new(2026, 10, 31)) ].each { |text| import_text(text) }

      household.journal_entries.includes(:postings).each { |entry| expect(entry.postings.sum(&:amount_paise)).to eq(0) }
      expect(household.bank_accounts.sole.reconciliation).to include(difference_paise: 0)
      expect(household.bank_transactions.count).to eq(history.size)
    end

    it "shows the gap when a month is missing" do
      import_text(statement(Date.new(2026, 8, 1), Date.new(2026, 8, 31)))
      import_text(statement(Date.new(2026, 10, 1), Date.new(2026, 10, 31)))

      september = history.select { |t| t.posted_on.month == 9 }.sum(&:amount_paise)
      expect(household.bank_accounts.sole.reconciliation[:difference_paise]).to eq(-september)
    end

    it "keeps identical same-day charges apart by running balance" do
      twin = SyntheticSbi::Txn.new(Date.new(2026, 11, 3), "WDL TFR UPI/DR/123456789012/MUSIC APP/ICIC/musicapp@icici/Subscription", -199_00)
      text = SyntheticSbi.render(rows: [ twin, twin ], opening_paise: 1_000_00, from: Date.new(2026, 11, 1), to: Date.new(2026, 11, 3))

      expect(import_text(text)).to have_attributes(new_rows_count: 2)
      expect(household.bank_transactions.pluck(:balance_after_paise)).to contain_exactly(801_00, 602_00)
    end

    it "refuses a statement whose opening contradicts one starting the same day" do
      import_text(statement(Date.new(2026, 8, 1), Date.new(2026, 8, 31)))
      forged = SyntheticSbi.statement_for(history, from: Date.new(2026, 8, 1), to: Date.new(2026, 9, 15), opening_paise: opening + 100)

      import = import_text(forged)
      expect(import).to be_rejected
      expect(import.error_message).to match(/opening balance .* disagrees/)
    end
  end
end
