namespace :leak do
  namespace :users do
    desc "Create a user and household on a private instance: bin/rails 'leak:users:create[mum@example.com,Sharma household]' " \
         "(PASSWORD=... to choose it, otherwise one is generated and printed once)"
    task :create, %i[ email household ] => :environment do |_, args|
      email = args.fetch(:email)
      abort "✗ #{email} already exists" if User.exists?(email_address: email.strip.downcase)

      password = ENV["PASSWORD"].presence || SecureRandom.base58(16)
      user = ActiveRecord::Base.transaction do
        household = Household.create!(name: args[:household].presence || "Household")
        household.users.create!(email_address: email, password: password)
      end
      puts "✓ Created #{user.email_address} in #{user.household.name}"
      puts "  Password: #{password}" unless ENV["PASSWORD"].present?
    end

    desc "Set a user's password: PASSWORD=... bin/rails 'leak:users:password[mum@example.com]' (signs out everywhere)"
    task :password, %i[ email ] => :environment do |_, args|
      user = User.find_by!(email_address: args.fetch(:email))
      password = ENV["PASSWORD"].presence || SecureRandom.base58(16)
      user.update!(password: password)
      user.sessions.destroy_all
      puts "✓ Password changed for #{user.email_address}"
      puts "  Password: #{password}" unless ENV["PASSWORD"].present?
    end

    desc "Delete a user's household: all its users, statements and findings: bin/rails 'leak:users:delete[mum@example.com]' CONFIRM=yes"
    task :delete, %i[ email ] => :environment do |_, args|
      household = User.find_by!(email_address: args.fetch(:email)).household
      abort "✗ This deletes #{household.name} and everything in it. Run again with CONFIRM=yes." unless ENV["CONFIRM"] == "yes"

      household.destroy!
      puts "✓ Deleted #{household.name}"
    end
  end

  desc "Print fresh secrets for a Kamal destination: bin/rails 'leak:secrets[private]' (README › Deploying)"
  task :secrets, %i[ destination ] do |_, args|
    require "securerandom"
    destination = args.fetch(:destination, "private")
    abort "✗ Destination is demo or private" unless %w[ demo private ].include?(destination)

    prefix = "LEAK_#{destination.upcase}_"
    {
      "SECRET_KEY_BASE" => SecureRandom.hex(64),
      "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => SecureRandom.alphanumeric(32),
      "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY" => SecureRandom.alphanumeric(32),
      "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT" => SecureRandom.alphanumeric(32),
      "POSTGRES_PASSWORD" => SecureRandom.alphanumeric(32)
    }.each { |name, value| puts "#{prefix}#{name}=#{value}" }
  end
end
