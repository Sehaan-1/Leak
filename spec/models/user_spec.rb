require "rails_helper"

RSpec.describe User do
  let(:household) { Household.create!(name: "Sharma household") }

  it "normalizes the email address" do
    user = household.users.create!(email_address: "  Asha@Example.COM ", password: "correct horse battery")
    expect(user.email_address).to eq("asha@example.com")
  end

  it "requires a household" do
    user = User.new(email_address: "asha@example.com", password: "correct horse battery")
    expect(user).not_to be_valid
    expect(user.errors[:household]).to be_present
  end

  it "rejects duplicate email addresses regardless of case" do
    household.users.create!(email_address: "asha@example.com", password: "correct horse battery")
    duplicate = household.users.build(email_address: "ASHA@example.com", password: "another password")
    expect(duplicate).not_to be_valid
  end

  it "never stores the plain password" do
    user = household.users.create!(email_address: "asha@example.com", password: "correct horse battery")
    expect(user.password_digest).not_to include("correct horse battery")
    expect(user.authenticate("correct horse battery")).to eq(user)
  end
end
