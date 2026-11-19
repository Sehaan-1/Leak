require "rails_helper"

RSpec.describe "API v1 findings" do
  let(:user) { create_user }

  it "requires a session" do
    get api_v1_findings_path, as: :json
    assert_response_schema_confirm(401)
  end

  it "is empty before any statement" do
    sign_in(user)
    get api_v1_findings_path, as: :json
    assert_response_schema_confirm(200)
    expect(json).to eq("findings" => [], "monthly_total_paise" => 0, "subscriptions_count" => 0)
  end

  context "with a year of statements" do
    before do
      import_demo!(user.household)
      sign_in(user)
    end

    def finding(kind)
      json["findings"].find { |item| item["kind"] == kind }
    end

    it "lists price increases and duplicates first, each pointing at its evidence" do
      get api_v1_findings_path, as: :json

      assert_response_schema_confirm(200)
      labels = json["findings"].map { |item| [ item["kind"], item.dig("series", "merchant", "slug") ] }
      expect(labels.first(2)).to eq([ %w[ price_increase netflix ], %w[ duplicate jiohotstar ] ])
      expect(labels.drop(2).map(&:first).uniq).to eq([ "subscription" ])

      expect(finding("price_increase")).to include("previous_amount_paise" => 499_00, "amount_paise" => 649_00,
        "dismissed" => false, "related_series" => nil,
        "step_charge" => include("posted_on" => "2026-07-05", "charged_paise" => 649_00))
      expect(finding("price_increase")["series"]).to include("cadence" => "monthly", "status" => "active",
        "charges_count" => 12, "merchant" => include("name" => "Netflix"))
      expect(finding("duplicate")).to include("amount_paise" => 149_00, "step_charge" => nil,
        "related_series" => include("amount_paise" => 299_00))
      expect(json).to include("subscriptions_count" => 4, "monthly_total_paise" => 649_00 + 119_00 + 299_00 + 149_00)
    end

    it "dismisses a finding, keeps it dismissed after detection runs again, and restores it" do
      get api_v1_findings_path, as: :json
      first_id = finding("price_increase")["id"]

      post api_v1_finding_dismissal_path(first_id), as: :json
      assert_response_schema_confirm(201)
      expect(json).to include("id" => first_id, "dismissed" => true)

      Detection::Run.new(household: user.household).call
      get api_v1_findings_path, as: :json
      rebuilt = finding("price_increase")
      expect(rebuilt["id"]).not_to eq(first_id)
      expect(rebuilt["dismissed"]).to be(true)
      expect(json["findings"].count { |item| item["dismissed"] }).to eq(1)

      delete api_v1_finding_dismissal_path(rebuilt["id"]), as: :json
      assert_response_schema_confirm(200)
      expect(json["dismissed"]).to be(false)
      expect(user.household.finding_dismissals).to be_empty
    end

    it "doesn't reach another household's findings" do
      other = create_household(name: "Neighbours")
      import_demo!(other)

      post api_v1_finding_dismissal_path(other.findings.first), as: :json
      assert_response_schema_confirm(404)
      expect(FindingDismissal.count).to eq(0)
    end
  end
end
