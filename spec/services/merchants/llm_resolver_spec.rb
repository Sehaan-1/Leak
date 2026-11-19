require "rails_helper"

RSpec.describe Merchants::LlmResolver do
  before { Merchants::Catalogue.sync! }

  let(:rules_answer) { "TO TRANSFER-UPI/DR/412345678901/SPOTIFY INDIA/UTIB/spotify.in@ybl/UPI--" }
  let(:insurer) { "ACH DR INW HDFC STANDARD LIFE 6617976069" }
  let(:friend) { "TO TRANSFER-UPI/DR/533276293463/DIVYA GUPTA/UTIB/divya.gu/Payment from Ph--" }
  let(:cafe) { "TO TRANSFER-UPI/DR/534252827384/CAFE MOCHA BANDRA/PUNB/cafe69/Sent from Paytm--" }

  # What the fake LLM says, by the row's narration: [label, confidence, evidence].
  let(:says) { {} }
  let(:client) do
    lookup = says
    FakeLlm.new do |row|
      label, confidence, evidence = lookup.find { |narration, _| Merchants::Llm::Prompt.mask(narration) == row["narration"] }&.last
      { "id" => row["id"], "label" => label, "confidence" => confidence, "evidence" => evidence } if label
    end
  end
  let(:resolver) { described_class.new(client: client) }

  it "sends only the rows the rules abstained on, masked, in one batch" do
    says[insurer] = [ "hdfc_life", 0.9, "HDFC STANDARD LIFE" ]
    says[friend] = [ "person", 0.95, "DIVYA GUPTA" ]
    results = resolver.resolve_many([ rules_answer, insurer, friend ])

    expect(results.map(&:label)).to eq(%w[ spotify hdfc_life person ])
    expect(results.map(&:via)).to eq(%w[ name_alias llm llm ])
    expect(results[1]).to have_attributes(counterparty: "merchant", model: "fake-model")
    expect(results[1].evidence).to include("HDFC STANDARD LIFE", "similarity 0.37")
    expect(client.requests.size).to eq(1)
    sent = FakeLlm.rows(client.requests.first[:messages])
    expect(sent.map { |row| row["id"] }).to eq(%w[ r1 r2 ])
    expect(sent.first).to include("channel" => "nach", "narration" => "ACH DR INW HDFC STANDARD LIFE #")
    expect(client.requests.first[:messages].to_s).not_to include("6617976069", "533276293463", "SPOTIFY INDIA/")
  end

  it "restricts the schema to catalogue slugs, person and unknown" do
    resolver.resolve_many([ cafe ])
    labels = client.requests.first[:schema].dig(:properties, :answers, :items, :properties, :label, :enum)
    expect(labels).to include("netflix", "hdfc_life", "person", "unknown")
    expect(labels.size).to eq(Merchant.count + 2)
  end

  it "keeps an honest unknown in review, with the LLM's reason" do
    says[cafe] = [ "unknown", 0.9, "CAFE MOCHA BANDRA" ]
    result = resolver.resolve_many([ cafe ]).first
    expect(result).to have_attributes(label: "abstain", via: "abstained", model: "fake-model")
    expect(result.evidence).to eq("LLM abstained: not in the catalogue: CAFE MOCHA BANDRA")
  end

  it "rejects evidence that isn't in the narration" do
    says[cafe] = [ "netflix", 0.99, "NETFLIX" ]
    expect(resolver.resolve_many([ cafe ]).first.evidence).to include("is not in the narration")
  end

  it "rejects a merchant the evidence doesn't point to" do
    says[insurer] = [ "hdfc_mf", 0.99, "HDFC STANDARD LIFE" ]
    result = resolver.resolve_many([ insurer ]).first
    expect(result.via).to eq("abstained")
    expect(result.evidence).to include("LLM said hdfc_mf", "doesn't match its names")
  end

  it "rejects low confidence, unknown labels and missing answers" do
    says[insurer] = [ "hdfc_life", 0.4, "HDFC STANDARD LIFE" ]
    says[friend] = [ "zomato_gold", 0.99, "DIVYA GUPTA" ]
    results = resolver.resolve_many([ insurer, friend, cafe ])
    expect(results.map(&:via)).to all(eq("abstained"))
    expect(results.map(&:evidence)).to match([ a_string_including("confidence 0.4 is below 0.7"),
      a_string_including("\"zomato_gold\" is not in the catalogue"), a_string_including("no answer for this row") ])
  end

  it "rejects person for a business-looking payee" do
    says[cafe] = [ "person", 0.99, "CAFE MOCHA BANDRA" ]
    expect(resolver.resolve_many([ cafe ]).first.evidence).to include("doesn't read like a personal name")
  end

  it "leaves rules results alone when no LLM is configured" do
    results = described_class.new(client: Merchants::Llm::NullClient.new).resolve_many([ rules_answer, cafe ])
    expect(results.map(&:via)).to eq(%w[ name_alias abstained ])
    expect(results.last.evidence).to start_with("no catalogue match")
  end

  describe "#resolve_pending!" do
    let(:household) { create_household }
    let!(:txn) do
      Statements::Importer.import_text(household: household, text: sample_text, filename: "s.pdf")
      household.bank_transactions.first.tap do |row|
        row.update!(narration: insurer)
        row.apply_resolution(Merchants::Resolver.new(household: household).resolve(insurer))
        row.save!
      end
    end

    it "saves accepted verdicts and doesn't ask about a row twice" do
      expect(txn).to have_attributes(resolution: "abstained", llm_checked_at: nil)
      says[insurer] = [ "hdfc_life", 0.9, "HDFC STANDARD LIFE" ]
      resolver = described_class.new(household: household, client: client)

      expect(resolver.resolve_pending!(household.bank_transactions)).to eq(1)
      expect(txn.reload).to have_attributes(resolution: "llm", counterparty: "merchant", resolution_model: "fake-model")
      expect(txn.merchant.slug).to eq("hdfc_life")
      expect(txn.llm_checked_at).to be_present
      expect(txn.resolution_evidence).to include("HDFC STANDARD LIFE")

      requests = client.requests.size
      expect(resolver.resolve_pending!(household.bank_transactions)).to eq(0)
      expect(client.requests.size).to eq(requests)
    end

    it "stamps rows the LLM declined, so they stay in review without being re-sent" do
      says[insurer] = [ "unknown", 0.9, "HDFC STANDARD LIFE" ]
      described_class.new(household: household, client: client).resolve_pending!(household.bank_transactions)
      expect(txn.reload).to have_attributes(resolution: "abstained", resolution_model: "fake-model")
      expect(txn.llm_checked_at).to be_present
      expect(household.bank_transactions.needs_review).to include(txn)
    end

    it "stamps nothing when the provider fails" do
      failing = FakeLlm.new.tap { |fake| def fake.complete(**) = raise(Merchants::Llm::Error, "HTTP 503") }
      expect { described_class.new(household: household, client: failing).resolve_pending!(household.bank_transactions) }
        .to raise_error(Merchants::Llm::Error)
      expect(txn.reload.llm_checked_at).to be_nil
    end
  end
end
