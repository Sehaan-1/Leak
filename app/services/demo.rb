# The public demo (LEAK_DEMO=1): anyone can try Leak on made-up data.
#
# Each visitor gets their own throwaway household, filled with a year of a
# fabricated SBI statement (lib/synthetic/demo_statement.rb) and deleted by
# Demo::CleanupJob a day later. Uploading statements is turned off, so no
# real statement can end up on the public server.
module Demo
  LIFETIME = 24.hours

  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("LEAK_DEMO", false)) || false
  end

  # A new demo household with a signed-in-able user. The user's password is
  # random and never shown: the demo session is the only way in.
  def self.create_user!(now: Time.current)
    ActiveRecord::Base.transaction do
      household = Household.create!(name: "Demo household", demo_expires_at: now + LIFETIME)
      user = household.users.create!(email_address: "demo-#{SecureRandom.hex(8)}@demo.invalid",
        password: SecureRandom.base58(32))
      populate!(household)
      user
    end
  end

  # Imports the demo statement like an upload, then runs detection straight
  # away rather than in the background job the import enqueues. Used by the
  # demo and by db/seeds.rb.
  def self.populate!(household)
    import = Statements::Importer.import_text(household: household, text: Synthetic::DemoStatement.text,
      filename: "demo-statement.pdf")
    raise "Demo statement didn't import: #{import.error_message}" if import.rejected?

    Detection::Run.new(household: household).call
    import
  end
end
