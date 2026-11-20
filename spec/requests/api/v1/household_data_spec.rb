require "rails_helper"

RSpec.describe "API v1 household data" do
  let(:user) { create_user }

  it "requires a session" do
    get api_v1_household_data_path, as: :json
    assert_response_schema_confirm(401)
    delete api_v1_household_data_path, as: :json
    assert_response_schema_confirm(401)
  end

  it "shows what Leak holds, deletes it all, and keeps the user signed in" do
    import_demo!(user.household)
    sign_in(user)

    get api_v1_household_data_path, as: :json
    assert_response_schema_confirm(200)
    expect(json).to eq("demo_expires_at" => nil, "counts" => {
      "statements" => 1, "transactions" => Synthetic::DemoStatement.txns.size, "subscriptions" => 4,
      "learned_merchants" => 0, "dismissed_findings" => 0
    })

    delete api_v1_household_data_path, as: :json
    assert_response_schema_confirm(200)
    expect(json["deleted"]).to include("statements" => 1, "subscriptions" => 4)

    get api_v1_findings_path, as: :json
    expect(response).to have_http_status(:ok)
    expect(json).to include("findings" => [], "subscriptions_count" => 0)
    get api_v1_household_data_path, as: :json
    expect(json["counts"].values).to all(eq(0))
  end

  it "needs the CSRF token, like every write" do
    sign_in(user)
    ActionController::Base.allow_forgery_protection = true
    delete api_v1_household_data_path, as: :json
    assert_response_schema_confirm(422)
  ensure
    ActionController::Base.allow_forgery_protection = false
  end
end
