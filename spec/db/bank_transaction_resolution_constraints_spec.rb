require "rails_helper"

RSpec.describe "bank_transactions resolution constraints" do
  let(:household) { create_household }
  # Created up front: a lazy import inside set!'s savepoint would be rolled back with it.
  let!(:txn) do
    Statements::Importer.import_text(household: household, text: sample_text, filename: "s.pdf")
    household.bank_transactions.first
  end
  let(:merchant) { Merchant.create!(slug: "acme", name: "Acme", category: "other") }

  def set!(**columns)
    assignments = columns.map { |column, value| "#{column} = #{value.nil? ? "NULL" : BankTransaction.connection.quote(value)}" }
    # A savepoint per statement, so one rejected UPDATE doesn't abort the rest.
    BankTransaction.transaction(requires_new: true) do
      BankTransaction.connection.execute("UPDATE bank_transactions SET #{assignments.join(", ")} WHERE id = #{txn.id}")
    end
  end

  it "accepts the states the resolver produces" do
    expect { set!(merchant_id: merchant.id, counterparty: "merchant", resolution: "name_alias", resolved_at: Time.current) }.not_to raise_error
    expect { set!(merchant_id: nil, counterparty: "person", resolution: "rule", resolved_at: Time.current) }.not_to raise_error
    expect { set!(merchant_id: nil, counterparty: nil, resolution: "abstained", resolved_at: Time.current) }.not_to raise_error
    expect { set!(merchant_id: nil, counterparty: nil, resolution: nil, resolved_at: nil) }.not_to raise_error
  end

  it "rejects a merchant without a merchant counterparty, and vice versa" do
    expect { set!(merchant_id: merchant.id, counterparty: "person", resolution: "rule", resolved_at: Time.current) }
      .to raise_error(ActiveRecord::StatementInvalid, /merchant_matches_counterparty/)
    expect { set!(merchant_id: nil, counterparty: "merchant", resolution: "name_alias", resolved_at: Time.current) }
      .to raise_error(ActiveRecord::StatementInvalid, /merchant_matches_counterparty/)
  end

  it "rejects an abstention with an answer, or an answer without a time" do
    expect { set!(merchant_id: nil, counterparty: "person", resolution: "abstained", resolved_at: Time.current) }
      .to raise_error(ActiveRecord::StatementInvalid, /resolution_consistent/)
    expect { set!(merchant_id: nil, counterparty: "bank", resolution: "rule", resolved_at: nil) }
      .to raise_error(ActiveRecord::StatementInvalid, /resolution_consistent/)
  end

  it "accepts an LLM verdict" do
    expect { set!(merchant_id: merchant.id, counterparty: "merchant", resolution: "llm", resolved_at: Time.current, resolution_model: "m") }
      .not_to raise_error
  end

  it "keeps a merchant that transactions point at" do
    set!(merchant_id: merchant.id, counterparty: "merchant", resolution: "name_alias", resolved_at: Time.current)
    expect(merchant.destroy).to be(false)
    expect(merchant.errors.full_messages.join).to match(/bank transactions/i)
    expect { BankTransaction.transaction(requires_new: true) { Merchant.where(id: merchant.id).delete_all } }
      .to raise_error(ActiveRecord::StatementInvalid, /RestrictViolation/)
  end
end
