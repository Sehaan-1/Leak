require "rails_helper"

RSpec.describe Demo::CleanupJob do
  it "deletes demo households a day after they were created, and nothing else" do
    Merchants::Catalogue.sync!
    real = create_user
    old = travel_to(25.hours.ago) { Demo.create_user! }
    fresh = Demo.create_user!

    described_class.perform_now

    expect(Household.where(id: old.household_id)).not_to exist
    expect(BankTransaction.where(household_id: old.household_id)).not_to exist
    expect(Household.where(id: [ fresh.household_id, real.household_id ]).count).to eq(2)
    expect(fresh.household.bank_transactions).to exist
  end

  it "is scheduled hourly in production" do
    schedule = YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "delete_expired_demo_households")
    expect(schedule).to include("class" => "Demo::CleanupJob")
  end
end
