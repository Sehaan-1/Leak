require "rails_helper"
require "rake"

RSpec.describe "lib/tasks/instance.rake" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("leak:users:create")
  end

  def run(name, *args)
    task = Rake::Task[name]
    task.reenable
    expect { task.invoke(*args) }.to output.to_stdout
  end

  it "creates a user in a new household and prints the generated password once" do
    output = capture_stdout { Rake::Task["leak:users:create"].tap(&:reenable).invoke("Mum@Example.com", "Sharma household") }

    user = User.find_by!(email_address: "mum@example.com")
    expect(user.household.name).to eq("Sharma household")
    password = output[/Password: (\S+)/, 1]
    expect(User.authenticate_by(email_address: "mum@example.com", password: password)).to eq(user)
  end

  it "deletes a household only with CONFIRM=yes" do
    user = create_user
    expect { Rake::Task["leak:users:delete"].tap(&:reenable).invoke(user.email_address) }
      .to raise_error(SystemExit).and output(/CONFIRM=yes/).to_stderr
    expect(Household.where(id: user.household_id)).to exist

    ENV["CONFIRM"] = "yes"
    run("leak:users:delete", user.email_address)
    expect(Household.where(id: user.household_id)).not_to exist
  ensure
    ENV.delete("CONFIRM")
  end

  it "prints a full set of secrets for a destination" do
    output = capture_stdout { Rake::Task["leak:secrets"].tap(&:reenable).invoke("demo") }
    names = output.lines.map { |line| line.split("=", 2).first }
    expect(names).to eq(%w[ SECRET_KEY_BASE ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
                            ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT POSTGRES_PASSWORD ].map { "LEAK_DEMO_#{_1}" })
    expect(File.read(Rails.root.join(".kamal/secrets.demo")).scan(/\$(LEAK_DEMO_\w+)/).flatten.uniq).to match_array(names)
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
