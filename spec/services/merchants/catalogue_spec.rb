require "rails_helper"

RSpec.describe Merchants::Catalogue do
  it "has no clashing, empty or uncategorised aliases" do
    expect(described_class.problems).to eq([])
    expect(described_class.entries.size).to be >= 50
  end

  it "syncs idempotently" do
    first = described_class.sync!
    counts = [ Merchant.count, MerchantAlias.count ]
    expect(described_class.sync!).to eq(first)
    expect([ Merchant.count, MerchantAlias.count ]).to eq(counts)
    expect(MerchantAlias.find_by!(kind: "name", pattern: "NETFLIXCOM").merchant.slug).to eq("netflix")
    expect(MerchantAlias.find_by!(kind: "vpa", pattern: "swiggy@icici").merchant.slug).to eq("swiggy")
  end

  it "moves and deletes catalogue aliases but keeps household ones and merchants" do
    entry = ->(slug, names, vpas = []) { described_class::Entry.new(slug, slug.titleize, "streaming", names.map { [ "name", _1 ] } + vpas.map { [ "vpa", _1 ] }) }
    described_class.sync!([ entry.("alpha", %w[ ALPHA SHARED ]), entry.("beta", %w[ BETA ], %w[ beta@icici ]) ])
    household = create_household
    MerchantAlias.create!(merchant: Merchant.find_by!(slug: "alpha"), household: household, kind: "name", pattern: "MYALPHA")

    described_class.sync!([ entry.("alpha", %w[ ALPHA ]), entry.("beta", %w[ BETA SHARED ]) ])

    expect(MerchantAlias.find_by!(pattern: "SHARED", household: nil).merchant.slug).to eq("beta")
    expect(MerchantAlias.exists?(pattern: "beta@icici")).to be(false)
    expect(MerchantAlias.exists?(pattern: "MYALPHA", household: household)).to be(true)
  end

  it "refuses a catalogue where one alias belongs to two merchants" do
    entries = [ described_class::Entry.new("a", "A", "other", [ [ "name", "SAME" ] ]),
                described_class::Entry.new("b", "B", "other", [ [ "name", "SAME" ] ]) ]
    expect { described_class.sync!(entries) }.to raise_error(ArgumentError, /name SAME belongs to a and b/)
  end
end
