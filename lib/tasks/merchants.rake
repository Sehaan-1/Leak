namespace :leak do
  namespace :merchants do
    desc "Sync config/merchants.yml into the merchant catalogue"
    task sync: :environment do
      result = Merchants::Catalogue.sync!
      puts "✓ Catalogue synced: #{result[:merchants]} merchants, #{result[:aliases]} aliases"
    end

    desc "Resolve merchants for a household's unresolved transactions: bin/rails 'leak:merchants:resolve[user@example.com]' (ALL=1 re-resolves every row)"
    task :resolve, %i[ email ] => :environment do |_, args|
      household = User.find_by!(email_address: args.fetch(:email)).household
      scope = household.bank_transactions
      scope = scope.where(resolution: nil) unless ENV["ALL"] == "1"
      count = 0
      resolver = Merchants::Resolver.new(household: household)
      scope.find_in_batches(batch_size: 500) do |batch|
        BankTransaction.transaction { resolver.resolve_all!(batch) }
        count += batch.size
      end
      puts "✓ Resolved #{count} transactions; #{household.bank_transactions.needs_review.count} need review"
    end
  end

  namespace :eval do
    desc "Write a synthetic labelled narration set: bin/rails 'leak:eval:generate[path,seed,count]'"
    task :generate, %i[ path seed count ] => :environment do |_, args|
      path = Rails.root.join(args.fetch(:path))
      config = Evaluation::Gate.config
      abort "✗ #{path} is the frozen golden set; make a new version instead" if path == Rails.root.join(config["golden"]) && path.exist?

      examples = Synthetic::Narrations.new(seed: Integer(args.fetch(:seed))).examples(Integer(args.fetch(:count)))
      Synthetic::Narrations.write_jsonl(path, examples)
      puts "✓ Wrote #{examples.size} examples to #{args[:path]} (sha256 #{Digest::SHA256.file(path).hexdigest})"
    end

    desc "Evaluate the merchant resolver: bin/rails 'leak:eval:merchants[golden]' (gated) or 'leak:eval:merchants[dev]' (lists errors)"
    task :merchants, %i[ set ] => :environment do |_, args|
      exit Evaluation::Gate.run(set: args[:set] || "golden")
    end
  end
end
