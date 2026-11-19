require "rails_helper"

RSpec.describe Merchants::LlmResolutionJob do
  before { Merchants::Catalogue.sync! }

  let(:household) { create_household }

  it "is enqueued after an import only when an LLM is configured" do
    expect { Statements::Importer.import_text(household: household, text: sample_text, filename: "s.pdf") }
      .not_to have_enqueued_job(described_class)

    allow(Merchants::Llm).to receive(:enabled?).and_return(true)
    expect { described_class.enqueue_for(household) }.to have_enqueued_job(described_class).with(household.id)
  end

  it "sends the household's rows in review to the LLM" do
    Statements::Importer.import_text(household: household, text: sample_text, filename: "s.pdf")
    household.bank_transactions.first.tap do |txn|
      txn.update!(narration: "ACH DR INW HDFC STANDARD LIFE 6617976069", merchant: nil, counterparty: nil, resolution: "abstained")
    end
    fake = FakeLlm.new { |row| { "id" => row["id"], "label" => "hdfc_life", "confidence" => 0.9, "evidence" => "HDFC STANDARD LIFE" } }
    allow(Merchants::Llm).to receive(:client).and_return(fake)

    described_class.perform_now(household.id)
    expect(household.bank_transactions.where(resolution: "llm").sole.merchant.slug).to eq("hdfc_life")
  end
end
