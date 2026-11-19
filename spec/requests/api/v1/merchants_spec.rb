require "rails_helper"

RSpec.describe "API v1 merchants" do
  it "requires a session" do
    get api_v1_merchants_path, as: :json
    assert_response_schema_confirm(401)
  end

  it "lists the catalogue by name" do
    Merchants::Catalogue.sync!
    sign_in(create_user)

    get api_v1_merchants_path, as: :json

    assert_response_schema_confirm(200)
    names = json["merchants"].map { |merchant| merchant["name"] }
    expect(names).to eq(names.sort_by(&:downcase))
    expect(json["merchants"]).to include(include("slug" => "youtube_premium", "name" => "YouTube Premium", "category" => "streaming"))
  end
end
