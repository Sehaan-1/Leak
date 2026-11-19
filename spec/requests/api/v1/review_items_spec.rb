require "rails_helper"

RSpec.describe "API v1 review queue" do
  let(:user) { create_user }
  let(:youtube) { Merchant.find_by!(slug: "youtube_premium") }

  it "requires a session" do
    get api_v1_review_items_path, as: :json
    assert_response_schema_confirm(401)
  end

  context "with a year of statements" do
    before do
      import_demo!(user.household)
      sign_in(user)
    end

    it "lists rows in review newest first, with the payee, UPI ID and why" do
      get api_v1_review_items_path, as: :json

      assert_response_schema_confirm(200)
      expect(json["total_count"]).to eq(12)
      items = json["review_items"]
      expect(items.map { |item| item["posted_on"] }).to eq(items.map { |item| item["posted_on"] }.sort.reverse)
      youtube_row = items.find { |item| item["upi_id"] == "youtube.premium@okaxis" }
      expect(youtube_row).to include("payee" => "GOOGLE PLAY", "amount_paise" => -149_00,
        "reason" => "payee and UPI ID point to different merchants")
    end

    it "resolves a row to a merchant, learns its UPI ID and clears the rows it matches" do
      row = review_row(user.household, "GOOGLE PLAY")

      post api_v1_review_item_resolution_path(row), as: :json, params: { counterparty: "merchant", merchant_id: youtube.id }

      assert_response_schema_confirm(200)
      expect(json).to include("review_item_id" => row.id, "counterparty" => "merchant",
        "merchant" => include("slug" => "youtube_premium"), "also_resolved_count" => 9,
        "learned" => { "kind" => "vpa", "pattern" => "youtube.premium@okaxis" })

      get api_v1_review_items_path, as: :json
      expect(json["total_count"]).to eq(2)
      get api_v1_findings_path, as: :json
      expect(json["findings"].map { |item| item.dig("series", "merchant", "slug") }).to include("youtube_premium")
    end

    it "resolves a row to a person without learning anything" do
      row = review_row(user.household, "SAI KRUPA")

      post api_v1_review_item_resolution_path(row), as: :json, params: { counterparty: "person" }

      assert_response_schema_confirm(200)
      expect(json).to include("counterparty" => "person", "merchant" => nil, "learned" => nil, "also_resolved_count" => 0)
    end

    it "needs a merchant when the answer is a merchant" do
      row = review_row(user.household, "GOOGLE PLAY")
      post api_v1_review_item_resolution_path(row), as: :json, params: { counterparty: "merchant" }
      assert_response_schema_confirm(422)
      expect(json.dig("error", "code")).to eq("merchant_required")
      expect(row.reload).to be_resolved_by_abstained
    end

    it "only takes rows that are in review" do
      resolved = user.household.bank_transactions.where.not(resolution: "abstained").first
      post api_v1_review_item_resolution_path(resolved), as: :json, params: { counterparty: "cash" }
      assert_response_schema_confirm(404)
    end

    it "shows merchants and review state on the transactions list" do
      get api_v1_bank_transactions_path, as: :json
      assert_response_schema_confirm(200)
      rows = json["bank_transactions"]
      # Statement text wraps, so a space can land anywhere in a narration.
      netflix = rows.find { |row| row["narration"].delete(" ").include?("netflix@icici") }
      expect(netflix).to include("counterparty" => "merchant", "needs_review" => false,
        "merchant" => include("name" => "Netflix"))
      expect(rows.find { |row| row["narration"].delete(" ").include?("GOOGLEPLAY") })
        .to include("counterparty" => nil, "merchant" => nil, "needs_review" => true)
    end
  end
end
