require "rails_helper"

RSpec.describe "API v1 me" do
  it "returns 401 JSON (not a redirect) without a session" do
    get api_v1_me_path, as: :json

    assert_response_schema_confirm(401)
    expect(json.dig("error", "code")).to eq("unauthorized")
  end

  it "returns the signed-in user and household" do
    user = create_user
    sign_in(user)
    get api_v1_me_path, as: :json

    assert_response_schema_confirm(200)
    expect(json).to eq(
      "user" => { "id" => user.id, "email_address" => user.email_address },
      "household" => { "id" => user.household.id, "name" => user.household.name }
    )
  end

  it "ignores a forged session cookie" do
    get api_v1_me_path, as: :json, headers: { "Cookie" => "session_id=1" }
    expect(response).to have_http_status(:unauthorized)
  end
end
