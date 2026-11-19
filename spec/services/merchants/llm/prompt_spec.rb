require "rails_helper"

RSpec.describe Merchants::Llm::Prompt do
  before { Merchants::Catalogue.sync! }

  let(:prompt) { described_class.new(catalogue: described_class.catalogue_for(nil)) }

  it "masks digit runs: references, account and phone numbers" do
    expect(described_class.mask("UPI/DR/412345678901/KABIR/IDIB/9308750822/Mandate 00976 AT 09482")).to eq("UPI/DR/#/KABIR/IDIB/#/Mandate # AT #")
    expect(described_class.mask("ZEE5 X4598")).to eq("ZEE5 X4598")
  end

  it "lists the catalogue with names and UPI IDs, in a stable order" do
    system = prompt.messages([]).first.fetch(:content)
    expect(system).to include("netflix: Netflix | NETFLIX, NETFLIXCOM, NETFLIXENTERTAINMENTSERVICES | netflix@icici, netflixupi.payu@hdfcbank")
    expect(prompt.catalogue.map(&:slug)).to eq(prompt.catalogue.map(&:slug).sort)
    expect(prompt.messages([])).to eq(described_class.new(catalogue: described_class.catalogue_for(nil)).messages([]))
  end

  it "includes a household's own aliases" do
    household = create_household
    MerchantAlias.create!(household: household, merchant: Merchant.find_by!(slug: "netflix"), kind: "name", pattern: "NFLXHOUSE")
    expect(described_class.catalogue_for(household).find { |entry| entry.slug == "netflix" }.names).to include("NFLXHOUSE")
    expect(described_class.catalogue_for(nil).find { |entry| entry.slug == "netflix" }.names).not_to include("NFLXHOUSE")
  end

  it "sends each row's parsed hints and masked narration as JSON lines" do
    parsed = Merchants::Narration.parse("TO TRANSFER-UPI/DR/412345678901/RAMESH K/SBIN/9876543210@ybl/Pay--")
    user = prompt.messages([ { id: "r1", parsed: parsed } ]).last.fetch(:content)
    # Structured fields are parsed space-free (statement wraps put spaces anywhere).
    expect(user.lines.last).to eq(JSON.generate(id: "r1", channel: "upi", payee: "RAMESHK", upi_id: '#@ybl',
      narration: 'TO TRANSFER-UPI/DR/#/RAMESH K/SBIN/#@ybl/Pay--'))
  end
end
