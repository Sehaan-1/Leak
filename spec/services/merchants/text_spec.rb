require "rails_helper"

RSpec.describe Merchants::Text do
  it "computes pg_trgm-style similarity" do
    expect(described_class.similarity("HDFCSTANDARDLIFE", "HDFCLIFE")).to be_within(0.001).of(0.368)
    expect(described_class.similarity("NETFLIX", "NETFLIX")).to eq(1.0)
    expect(described_class.similarity("", "NETFLIX")).to eq(0.0)
  end

  it "agrees with PostgreSQL" do
    pairs = [ %w[ HDFCSTANDARDLIFE HDFCLIFE ], %w[ BAJAJFINLTD BAJAJFINANCE ], %w[ LIFEINSURANCECORPN LIFEINSURANCECORPORATION ] ]
    pairs.each do |left, right|
      expected = ActiveRecord::Base.connection.select_value(ActiveRecord::Base.sanitize_sql_array([ "SELECT similarity(?, ?)", left, right ]))
      expect(described_class.similarity(left, right)).to be_within(0.0001).of(expected.to_f)
    end
  end
end
