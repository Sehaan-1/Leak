require "rails_helper"

RSpec.describe "App shell and HTML sign-in" do
  context "with forgery protection on, as in production" do
    around do |example|
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      example.run
    ensure
      ActionController::Base.allow_forgery_protection = original
    end

    it "serves the SPA shell to anyone, with the CSRF token and text-scale opt-in" do
      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<div id="root"></div>', 'name="csrf-token"', 'name="text-scale"')
    end
  end

  it "points the shell at the built SPA when a Vite manifest exists" do
    manifest = { "src/main.tsx" => { "file" => "assets/main-abc123.js", "css" => [ "assets/main-def456.css" ] } }
    allow(ViteHelper::MANIFEST).to receive_messages(exist?: true, read: manifest.to_json)

    get root_path

    expect(response.body).to include('src="/spa/assets/main-abc123.js"', 'href="/spa/assets/main-def456.css"')
  end

  it "still signs in through the HTML form and lands on the app" do
    household = Household.create!(name: "Sharma household")
    household.users.create!(email_address: "asha@example.com", password: "correct horse battery")

    post session_path, params: { email_address: "asha@example.com", password: "correct horse battery" }

    expect(response).to redirect_to(root_url)
    expect(response.cookies["session_id"]).to be_present
  end
end
