require "rails_helper"

RSpec.describe Household do
  let(:user) { create_user }
  let(:household) { user.household }

  before do
    import_demo!(household)
    youtube = Merchant.find_by!(slug: "youtube_premium")
    Merchants::ManualResolution.new(household: household)
      .call(review_row(household, "GOOGLE PLAY"), counterparty: "merchant", merchant: youtube)
    finding = household.findings.kind_price_increase.sole
    household.finding_dismissals.create!(kind: finding.kind, bank_transaction_id: finding.step_transaction_id)
    user.sessions.create!(user_agent: "spec", ip_address: "127.0.0.1")
  end

  # Tables that hold a household's data, by household_id.
  def rows_left(household_id)
    %w[ accounts journal_entries postings bank_accounts statement_imports bank_transactions
        recurring_series recurring_series_charges findings finding_dismissals merchant_aliases ].to_h do |table|
      [ table, ActiveRecord::Base.connection.select_value("SELECT count(*) FROM #{table} WHERE household_id = #{household_id.to_i}") ]
    end
  end

  it "counts what it holds" do
    expect(household.data_counts).to eq(statements: 1, transactions: Synthetic::DemoStatement.txns.size,
      subscriptions: 5, learned_merchants: 1, dismissed_findings: 1)
  end

  describe "#erase_data!" do
    it "deletes everything imported, detected and learnt, and keeps the sign-in" do
      other = create_user(household: Household.create!(name: "Other"), email_address: "other@example.com")
      import_demo!(other.household)

      deleted = household.erase_data!

      expect(deleted).to include(statements: 1, transactions: Synthetic::DemoStatement.txns.size)
      expect(rows_left(household.id).values).to all(eq(0))
      expect(household.reload.users).to eq([ user ])
      expect(user.sessions).to exist
      expect(other.household.bank_transactions.count).to eq(Synthetic::DemoStatement.txns.size)
      expect(MerchantAlias.where(household: nil)).to exist
    end

    it "lets the household import the same statement again" do
      household.erase_data!
      import_demo!(household)
      expect(household.findings.kind_price_increase.count).to eq(1)
    end
  end

  describe "#destroy" do
    it "deletes the household, its users and sessions and all its data" do
      household_id = household.id

      household.destroy!

      expect(rows_left(household_id).values).to all(eq(0))
      expect(User.where(id: user.id)).not_to exist
      expect(Session.where(user_id: user.id)).not_to exist
    end
  end
end
