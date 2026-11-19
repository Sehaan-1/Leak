require "rails_helper"

RSpec.describe MerchantAlias do
  let(:merchant) { Merchant.create!(slug: "acme", name: "Acme", category: "other") }

  it "only accepts normalised patterns" do
    expect(described_class.new(merchant: merchant, kind: "name", pattern: "ACME")).to be_valid
    expect(described_class.new(merchant: merchant, kind: "name", pattern: "Acme Ltd")).not_to be_valid
    expect(described_class.new(merchant: merchant, kind: "vpa", pattern: "acme@icici")).to be_valid
    expect(described_class.new(merchant: merchant, kind: "vpa", pattern: "ACME@icici")).not_to be_valid
  end

  it "is enforced by the database too" do
    sql = ->(kind, pattern) { "INSERT INTO merchant_aliases (merchant_id, kind, pattern, created_at, updated_at) VALUES (#{merchant.id}, '#{kind}', '#{pattern}', now(), now())" }
    expect { described_class.connection.execute(sql.("name", "acme ltd")) }.to raise_error(ActiveRecord::StatementInvalid, /pattern_normalised/)
  end

  it "allows one catalogue alias per pattern, plus one per household" do
    household = create_household
    described_class.create!(merchant: merchant, kind: "name", pattern: "ACME")
    described_class.create!(merchant: merchant, household: household, kind: "name", pattern: "ACME")
    expect { described_class.create!(merchant: merchant, kind: "name", pattern: "ACME") }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
