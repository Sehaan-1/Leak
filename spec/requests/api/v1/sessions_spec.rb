require "rails_helper"

RSpec.describe "API v1 sessions" do
  let!(:user) { create_user }

  describe "POST /api/v1/session" do
    it "signs in with an httpOnly session cookie and returns the user" do
      sign_in(user)

      assert_request_schema_confirm
      assert_response_schema_confirm(201)
      expect(json.dig("user", "email_address")).to eq("asha@example.com")
      expect(json.dig("household", "name")).to eq("Sharma household")
      expect(response.headers["Set-Cookie"]).to match(/session_id=.*httponly/i)
      expect(user.sessions.count).to eq(1)
    end

    it "normalizes the email address" do
      post api_v1_session_path, as: :json,
        params: { session: { email_address: "  ASHA@Example.com ", password: "correct horse battery" } }
      expect(response).to have_http_status(:created)
    end

    it "rejects a wrong password without saying which field was wrong" do
      post api_v1_session_path, as: :json,
        params: { session: { email_address: user.email_address, password: "nope" } }

      assert_response_schema_confirm(401)
      expect(json.dig("error", "code")).to eq("invalid_credentials")
      expect(response.headers["Set-Cookie"].to_s).not_to include("session_id=")
    end

    it "returns 400 when the session object is missing" do
      post api_v1_session_path, as: :json, params: { email_address: user.email_address }

      assert_response_schema_confirm(400)
    end
  end

  describe "DELETE /api/v1/session" do
    it "signs out and invalidates the session server-side" do
      sign_in(user)
      delete api_v1_session_path, as: :json

      assert_response_schema_confirm(204)
      expect(user.sessions.count).to eq(0)

      get api_v1_me_path, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "requires a session" do
      delete api_v1_session_path, as: :json
      assert_response_schema_confirm(401)
    end
  end

  describe "CSRF protection" do
    around do |example|
      ActionController::Base.allow_forgery_protection = true
      example.run
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    it "rejects writes without a CSRF token" do
      post api_v1_session_path, as: :json,
        params: { session: { email_address: user.email_address, password: "correct horse battery" } }

      assert_response_schema_confirm(422)
      expect(json.dig("error", "code")).to eq("invalid_csrf_token")
      expect(user.sessions.count).to eq(0)
    end
  end
end
