require "rails_helper"

RSpec.describe Ledger do
  let(:household) { create_household }
  let(:bank) { create_account(household, name: "SBI Savings", kind: "asset") }
  let(:netflix) { create_account(household, name: "Netflix", kind: "expense") }
  let(:on) { Date.new(2026, 11, 3) }

  describe ".post!" do
    it "writes a balanced entry and updates balances" do
      entry = described_class.post!(household: household, occurred_on: on, memo: "NETFLIX",
        lines: [ [ netflix, 649_00 ], [ bank, -649_00 ] ])
      check_deferred_constraints!

      expect(entry.postings.pluck(:amount_paise)).to contain_exactly(649_00, -649_00)
      expect(netflix.balance_paise).to eq(649_00)
      expect(bank.balance_paise).to eq(-649_00)
    end

    it "rejects unbalanced lines before touching the database" do
      expect {
        described_class.post!(household: household, occurred_on: on, memo: "x",
          lines: [ [ netflix, 649_00 ], [ bank, -600_00 ] ])
      }.to raise_error(Ledger::InvalidEntry, /off by ₹49.00/)
      expect(JournalEntry.count).to eq(0)
    end

    it "rejects a single line" do
      expect {
        described_class.post!(household: household, occurred_on: on, memo: "x", lines: [ [ netflix, 649_00 ] ])
      }.to raise_error(Ledger::InvalidEntry, /at least two/)
    end

    it "rejects non-integer amounts (no floats, no BigDecimal)" do
      [ 649.0, BigDecimal("649"), "649", 0 ].each do |bad|
        expect {
          described_class.post!(household: household, occurred_on: on, memo: "x",
            lines: [ [ netflix, bad ], [ bank, -64900 ] ])
        }.to raise_error(Ledger::InvalidEntry, /Integer paise/)
      end
    end

    it "rejects accounts from another household" do
      other_bank = create_account(create_household(name: "Other"), name: "Their bank", kind: "asset")
      expect {
        described_class.post!(household: household, occurred_on: on, memo: "x",
          lines: [ [ netflix, 649_00 ], [ other_bank, -649_00 ] ])
      }.to raise_error(Ledger::InvalidEntry, /belong to household/)
    end
  end

  # Property: for any sequence of balanced entries over random accounts, every
  # entry balances, the trial balance is zero, and each account's balance is
  # the sum of what was posted to it. Seeded from RSpec's --seed, so a failure
  # is reproducible with `rspec --seed <n>`.
  describe "trial balance property" do
    it "holds for random balanced entries" do
      rng = Random.new(RSpec.configuration.seed)
      accounts = Array.new(6) { |i| create_account(household, name: "Account #{i}", kind: (Account::KINDS - [ "suspense" ]).sample(random: rng)) }
      expected = Hash.new(0)

      40.times do |n|
        legs = rng.rand(1..4)
        amounts = Array.new(legs) { rng.rand(1..10_000_000) * (rng.rand < 0.5 ? 1 : -1) }
        amounts << -amounts.sum
        amounts.reject!(&:zero?)
        next if amounts.size < 2

        lines = amounts.map { |amount| [ accounts.sample(random: rng), amount ] }
        lines.each { |account, amount| expected[account.id] += amount }
        described_class.post!(household: household, occurred_on: on + n, memo: "entry #{n}", lines: lines)
      end
      check_deferred_constraints!

      expect(Posting.where(household: household).sum(:amount_paise)).to eq(0)
      household.journal_entries.includes(:postings).each do |entry|
        expect(entry.postings.sum(&:amount_paise)).to eq(0)
      end
      balances = household.accounts.with_balances.to_h { |a| [ a.id, a.balance_paise ] }
      accounts.each { |a| expect(balances[a.id]).to eq(expected[a.id]) }
    end
  end
end
