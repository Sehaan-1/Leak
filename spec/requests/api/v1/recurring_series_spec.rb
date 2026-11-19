require "rails_helper"

RSpec.describe "API v1 recurring series" do
  let(:user) { create_user }

  before { import_demo!(user.household) }

  it "requires a session" do
    get api_v1_recurring_series_path(user.household.recurring_series.first), as: :json
    assert_response_schema_confirm(401)
  end

  it "shows a series' charges oldest first, with the price step marked" do
    sign_in(user)
    netflix = user.household.recurring_series.joins(:merchant).find_by!(merchants: { slug: "netflix" })

    get api_v1_recurring_series_path(netflix), as: :json

    assert_response_schema_confirm(200)
    expect(json).to include("flagged" => true, "amount_paise" => 649_00, "charges_count" => 12,
      "merchant" => include("slug" => "netflix", "category" => "streaming"))
    charges = json["charges"]
    expect(charges.map { |charge| charge["posted_on"] }).to eq(charges.map { |charge| charge["posted_on"] }.sort)
    expect(charges.map { |charge| charge["charged_paise"] }.tally).to eq(499_00 => 7, 649_00 => 5)
    expect(charges.map { |charge| charge["level"] }.uniq).to eq([ 0, 1 ])
    step = charges.select { |charge| charge["price_step"] }
    expect(step.sole).to include("posted_on" => "2026-07-05", "charged_paise" => 649_00)
    # Statement text wraps, so a space can land anywhere in a narration.
    expect(step.sole["narration"].delete(" ")).to include("netflix@icici")
    expect(json["findings"].map { |item| item["kind"] }).to eq(%w[ price_increase subscription ])
  end

  it "answers 404 for a series detection has since replaced, or another household's" do
    sign_in(user)
    old_id = user.household.recurring_series.first.id
    Detection::Run.new(household: user.household).call

    get api_v1_recurring_series_path(old_id), as: :json
    assert_response_schema_confirm(404)

    other = create_household(name: "Neighbours")
    import_demo!(other)
    get api_v1_recurring_series_path(other.recurring_series.first), as: :json
    assert_response_schema_confirm(404)
  end
end
