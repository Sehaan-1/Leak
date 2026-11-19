module RequestHelpers
  def create_user(household: Household.create!(name: "Sharma household"),
                  email_address: "asha@example.com", password: "correct horse battery")
    household.users.create!(email_address: email_address, password: password)
  end

  def sign_in(user, password: "correct horse battery")
    post api_v1_session_path, as: :json,
      params: { session: { email_address: user.email_address, password: password } }
    expect(response).to have_http_status(:created)
  end

  def json
    response.parsed_body
  end
end
