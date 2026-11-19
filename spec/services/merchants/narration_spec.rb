require "rails_helper"

RSpec.describe Merchants::Narration do
  def parse(text) = described_class.parse(text)

  it "reads a UPI narration even when the statement wrap split its words" do
    parsed = parse("WDL TFR UPI/DR/630528391044/METRO MART/HDFC/metromart@hdfcbank/Grocerie s 0097696162090 AT 09482 BIDHANNAGAR")
    expect(parsed).to have_attributes(channel: :upi, payee: "METROMART", vpa: "metromart@hdfcbank", vpa_local: "metromart")
    expect(parsed.payee_key).to eq("METROMART")

    split = parse("TO TRANSFER-UPI/DR/412345678901/SWIGG Y/ICIC/swig gy@ic ici/Payment fo--")
    expect(split).to have_attributes(channel: :upi, payee: "SWIGGY", vpa: "swiggy@icici")
  end

  it "keeps a UPI ID the bank cut short, with or without its domain" do
    expect(parse("TO TRANSFER-UPI/DR/412345678901/SWIGGY L/YESB/swiggy.stor/Payment f--"))
      .to have_attributes(vpa: nil, vpa_local: "swiggy.stor")
    expect(parse("TO TRANSFER-UPI/DR/412345678901/ZOMATO/HDFC/zomato@hd/UPI--"))
      .to have_attributes(vpa: "zomato@hd", vpa_local: "zomato")
    expect(parse("TO TRANSFER-UPI/DR/412345678901/ZOMATO/HDFC/ab/UPI--")).to have_attributes(vpa: nil, vpa_local: nil)
  end

  it "reads NEFT and IMPS beneficiaries in both SBI layouts" do
    expect(parse("BY TRANSFER-NEFT*HDFC0001234*N123456789012*ROHAN DAS")).to have_attributes(channel: :neft, payee: "ROHANDAS")
    expect(parse("DEP TFR NEFT/UTR226309152102/TECH SOLUTIONS PVT LTD/Reimbursement 0020196526631 AT 09482 BIDHANNAGAR"))
      .to have_attributes(channel: :neft, payee: "TECHSOLUTIONSPVTLTD")
    expect(parse("TO TRANSFER-IMPS/P2A/412345678901/MEERAIYER/HDFC/X1234")).to have_attributes(channel: :imps, payee: "MEERAIYER")
  end

  it "recognises cash, bank charges and interest, NACH, bill payments and cards" do
    expect(parse("ATM WDL-ATM CASH 162090 BIDHANNAGAR").channel).to eq(:cash)
    expect(parse("CSH DEP (CDM) 123456 THANE").channel).to eq(:cash)
    expect(parse("INT.PD 01-04-2026 TO 30-09-2026").channel).to eq(:bank)
    expect(parse("DEBIT CARD ANNUAL FEE + GST").channel).to eq(:bank)
    expect(parse("ACH DR INW BAJAJ FINANCE LTD 2938749238").channel).to eq(:nach)
    expect(parse("NACH-DR-LIC OF INDIA-1234567890").channel).to eq(:nach)
    expect(parse("TO TRANSFER-INB BillPay MSEDCL 170012345678").channel).to eq(:bill)
    expect(parse("POS 459150XXXXXX1234 NETFLIX.COM").channel).to eq(:card)
    expect(parse("TO TRANSFER-INB ROHAN DAS").channel).to eq(:other)
  end
end
