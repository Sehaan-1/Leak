require "rails_helper"

RSpec.describe Merchants::Resolver do
  before { Merchants::Catalogue.sync! }

  let(:household) { create_household }
  let(:resolver) { described_class.new(household: household) }

  def resolve(narration) = resolver.resolve(narration)
  def label(narration) = resolve(narration).label

  describe "UPI" do
    it "trusts an exact catalogue UPI ID over everything else" do
      result = resolve("WDL TFR UPI/DR/412345678901/SOME PAYEE/HDFC/netflixupi.payu@hdfcbank/Mandate 0097612 AT 09482 X")
      expect(result).to have_attributes(label: "netflix", counterparty: "merchant", via: "vpa_alias")
      expect(result.evidence).to include("netflixupi.payu@hdfcbank")
    end

    it "matches a payee name exactly, by catalogue prefix, or as a truncation" do
      expect(resolve("TO TRANSFER-UPI/DR/412345678901/SPOTIFY INDIA/UTIB/spotify.in@ybl/UPI--"))
        .to have_attributes(label: "spotify", via: "name_alias")
      expect(label("TO TRANSFER-UPI/DR/412345678901/SWIGGY LIMITED/ICIC/random.gw@icici/UPI--")).to eq("swiggy")
      expect(label("TO TRANSFER-UPI/DR/412345678901/NOVI DIGI/ICIC/nd.gw@icici/UPI--")).to eq("jiohotstar")
    end

    it "uses the part of a cut-short UPI ID before the @" do
      expect(resolve("TO TRANSFER-UPI/DR/412345678901/BILLDESK/HDFC/msedcl.billdesk/Payment--"))
        .to have_attributes(label: "msedcl", via: "vpa_alias")
      expect(label("TO TRANSFER-UPI/DR/412345678901/XYZ/HDFC/zomatoorder/UPI--")).to eq("zomato")
    end

    it "reads through spaces the statement wrap put inside words" do
      expect(label("TO TRANSFER-UPI/DR/412345678901/NETF LIX/YESB/netfl ixupi.payu@hdf cbank/UPI--")).to eq("netflix")
    end

    it "abstains when the payee and the UPI ID point to different merchants" do
      expect(resolve("TO TRANSFER-UPI/DR/412345678901/SWIGGY/ICIC/zomatoorder/UPI--"))
        .to have_attributes(label: "abstain", via: "abstained")
    end

    it "calls an individual a person only when the UPI ID looks personal too" do
      expect(resolve("DEP TFR UPI/CR/630519482710/ANANYA ROY/UTIB/ananya.roy@okaxis/Transfer 0097738 AT 09482 X"))
        .to have_attributes(label: "person", counterparty: "person", via: "rule")
      expect(label("TO TRANSFER-UPI/DR/412345678901/KABIR SEN/YESB/9876543210@ybl/UPI--")).to eq("person")
      expect(label("TO TRANSFER-UPI/DR/412345678901/FRESH HARVEST/PUNB/q123456789@ybl/UPI--")).to eq("abstain")
      expect(label("TO TRANSFER-UPI/DR/412345678901/SAI MEDICAL AND GENERAL/HDFC/sai42@ybl/UPI--")).to eq("abstain")
      expect(label("TO TRANSFER-UPI/DR/412345678901/MEERA IYER/HDFC/cloudpay@yesbank/UPI--")).to eq("abstain")
    end

    it "abstains on businesses that aren't in the catalogue, including near-misses" do
      expect(label("WDL TFR UPI/DR/412345678901/OLA ELECTRIC SERVICE CENTRE/HDFC/q823749823@ybl/UPI 0097 AT 09482 X"))
        .to eq("abstain")
      expect(label("WDL TFR UPI/DR/412345678901/APOLLO TYRES SHOWROOM/HDFC/paytmqr2810050501011@paytm/UPI")).to eq("abstain")
    end
  end

  describe "cards, NACH and bill payments" do
    it "prefers the longest catalogue name in a card descriptor" do
      expect(label("DEBIT CARD-OTHPG 459150XXXXXX1234 AMAZON PRIME MEMBERSHIP")).to eq("amazon_prime")
      expect(label("POS 524193XXXXXX9876 WWW.AMAZON.IN")).to eq("amazon")
      expect(label("INTL POS TXN 607152XXXXXX1111 OPENAI *CHATGPT SUBSCR SAN FRANCISCO USD 20.00")).to eq("openai")
      expect(label("ECOM PUR 459150XXXXXX1234 GOOGLE *YOUTUBE PREMIUM")).to eq("youtube_premium")
    end

    it "matches short catalogue names only as whole words" do
      expect(label("NACH-DR-LIC OF INDIA-1234567890")).to eq("lic")
      expect(label("ACH DR INW LICI PREMIUM 2938749238")).to eq("lic")
      expect(label("POS 459150XXXXXX1234 UBER *TRIP HELP.UBER.COM")).to eq("uber")
      expect(label("POS 459150XXXXXX1234 SUBERB FOODS")).to eq("abstain")
    end

    it "resolves SIPs, EMIs and bill payments, which detection must later treat as decoys" do
      expect(label("DEBIT-ACHDr INDIAN CLEARING CORP 0000123456")).to eq("iccl")
      expect(label("ACH DR INW BAJAJ FINANCE LTD 2938749238")).to eq("bajaj_finance")
      expect(label("TO TRANSFER-INB BillPay TATA POWER-DDL 170012345678")).to eq("tata_power")
      expect(label("BBPS/MAHAVITARAN/170012345678/123456")).to eq("msedcl")
    end

    it "falls back to pg_trgm similarity only when one merchant clearly wins" do
      result = resolve("TO TRANSFER-INB BillPay MAHARASHTRA STATE ELECTRICTY 170012345678")
      expect(result).to have_attributes(label: "msedcl", via: "trigram")
      expect(result.evidence).to match(/similarity 0\.\d\d/)
      expect(label("TO TRANSFER-INB BillPay ZZQX UTILITY 170012345678")).to eq("abstain")
    end
  end

  it "recognises transfers to people, salary, cash and the bank's own entries" do
    expect(label("BY TRANSFER-NEFT*HDFC0001234*N123456789012*ROHAN DAS")).to eq("person")
    expect(label("TO TRANSFER-IMPS/P2A/412345678901/MEERAIYER/HDFC/X1234")).to eq("person")
    expect(label("BY TRANSFER-NEFT*ICIC0000104*CMS123456*ACME TECHNOLOGIES PVT LTD")).to eq("abstain")
    expect(label("ATM WDL-ATM CASH 162090 BIDHANNAGAR")).to eq("cash")
    expect(label("CREDIT INTEREST")).to eq("bank")
    expect(label("SMS CHGS QTR ENDING SEP 2026")).to eq("bank")
  end

  it "lets a household's own aliases override the catalogue, for that household only" do
    music = Merchant.find_by!(slug: "spotify")
    MerchantAlias.create!(merchant: music, household: household, kind: "name", pattern: "MUSICAPP")
    narration = "TO TRANSFER-UPI/DR/412345678901/MUSIC APP/ICIC/musicapp@icici/Subscription--"

    expect(described_class.new(household: household).resolve(narration).label).to eq("spotify")
    expect(described_class.new(household: create_household(name: "Other")).resolve(narration).label).to eq("abstain")
  end

  it "saves its verdicts on bank transactions" do
    import = Statements::Importer.import_text(household: household, text: sample_text, filename: "s.pdf")
    expect(import).to be_imported

    rows = household.bank_transactions.order(:posted_on, :position).pluck(:narration, :counterparty, :resolution)
    expect(rows.map { |_, counterparty, resolution| [ counterparty, resolution ] }).to all(satisfy { |c, r| r.present? && (c.present? || r == "abstained") })
    expect(rows.find { |narration, *| narration.include?("ANANYA") }).to include("person", "rule")
    expect(rows.find { |narration, *| narration.include?("METRO") }).to include(nil, "abstained")
    expect(household.bank_transactions.needs_review.count).to be_positive
    expect(household.bank_transactions.where.not(resolved_at: nil).count).to eq(7)
  end
end
