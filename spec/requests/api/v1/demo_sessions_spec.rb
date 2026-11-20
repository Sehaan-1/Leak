require "rails_helper"

RSpec.describe "API v1 demo sessions" do
  context "on a private instance" do
    it "doesn't exist" do
      post api_v1_demo_session_path, as: :json
      assert_response_schema_confirm(404)
      expect(Household.count).to eq(0)
    end

    it "keeps uploads and leaves the demo marker out of the page" do
      get root_path
      expect(response.body).not_to include("leak-demo")
    end
  end

  context "on the public demo" do
    before do
      allow(Demo).to receive(:enabled?).and_return(true)
      Merchants::Catalogue.sync!
    end

    it "marks the page so the sign-in screen offers the demo" do
      get root_path
      expect(response.body).to include('<meta name="leak-demo" content="1">')
    end

    it "creates a throwaway household of made-up data and signs in to it" do
      freeze_time do
        post api_v1_demo_session_path, as: :json

        assert_response_schema_confirm(201)
        expect(json.dig("household", "demo_expires_at")).to eq(1.day.from_now.iso8601)
        expect(json.dig("user", "email_address")).to end_with("@demo.invalid")
      end

      get api_v1_findings_path, as: :json
      expect(json).to include("subscriptions_count" => 4)
      get api_v1_review_items_path, as: :json
      expect(json["total_count"]).to eq(12)
    end

    it "gives every visitor their own household" do
      post api_v1_demo_session_path, as: :json
      first = json.dig("household", "id")
      delete api_v1_session_path, as: :json

      post api_v1_demo_session_path, as: :json
      expect(json.dig("household", "id")).not_to eq(first)
    end

    it "turns statement upload off" do
      post api_v1_demo_session_path, as: :json

      post api_v1_statement_imports_path,
        params: { file: Rack::Test::UploadedFile.new(StatementFixtures::SAMPLE_PDF, "application/pdf") }

      assert_response_schema_confirm(403)
      expect(json.dig("error", "code")).to eq("demo_uploads_disabled")
    end
  end
end
