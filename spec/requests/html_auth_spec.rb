require "rails_helper"

RSpec.describe "HTML sign-in" do
  it "redirects anonymous visitors to the sign-in page" do
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "signs in through the form and lands on the home page" do
    household = Household.create!(name: "Sharma household")
    household.users.create!(email_address: "asha@example.com", password: "correct horse battery")

    post session_path, params: { email_address: "asha@example.com", password: "correct horse battery" }
    follow_redirect!

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Signed in as asha@example.com")
  end
end
