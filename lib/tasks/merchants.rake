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

    desc "Send a household's rows in review to the LLM resolver now: bin/rails 'leak:merchants:llm[user@example.com]'"
    task :llm, %i[ email ] => :environment do |_, args|
      household = User.find_by!(email_address: args.fetch(:email)).household
      resolver = Merchants::LlmResolver.new(household: household)
      abort "✗ No LLM provider configured (see config/llm.yml)" unless resolver.enabled?

      resolved = resolver.resolve_pending!(household.bank_transactions)
      puts "✓ #{resolver.client.name} (#{resolver.client.model || "default model"}) resolved #{resolved} rows; " \
        "#{household.bank_transactions.needs_review.count} still need review"
    end
  end

  namespace :llm do
    desc "Show which LLM provider the merchant resolver would use, and try it on a synthetic narration"
    task check: :environment do
      Merchants::Catalogue.sync!
      resolver = Merchants::LlmResolver.new
      abort "✗ No LLM provider configured: abstentions go straight to review (see config/llm.yml)" unless resolver.enabled?

      puts "Provider: #{resolver.client.name}, model: #{resolver.client.model || "the agent's default"}"
      sample = "ACH DR INW HDFC STANDARD LIFE 6617976069"
      result = resolver.resolve_many([ sample ]).first
      puts "#{sample.inspect} -> #{result.label} via #{result.via}: #{result.evidence}"
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

    desc "Write synthetic labelled histories for the detection eval: bin/rails 'leak:eval:generate_histories[path,seed,count]'"
    task :generate_histories, %i[ path seed count ] => :environment do |_, args|
      path = Rails.root.join(args.fetch(:path))
      config = Evaluation::DetectionGate.config
      abort "✗ #{path} is the frozen golden set; make a new version instead" if path == Rails.root.join(config["golden"]) && path.exist?

      histories = Synthetic::Histories.new(seed: Integer(args.fetch(:seed))).histories(Integer(args.fetch(:count)))
      Synthetic::Histories.write_jsonl(path, histories)
      puts "✓ Wrote #{histories.size} histories (#{histories.sum { _1.txns.size }} transactions) to #{args[:path]} " \
        "(sha256 #{Digest::SHA256.file(path).hexdigest})"
    end

    desc "Evaluate recurring-charge detection: bin/rails 'leak:eval:detection[golden]' (gated) or 'leak:eval:detection[dev]' (lists errors)"
    task :detection, %i[ set ] => :environment do |_, args|
      exit Evaluation::DetectionGate.run(set: args[:set] || "golden")
    end

    desc "Evaluate the merchant resolver: bin/rails 'leak:eval:merchants[golden]' (gated) or 'leak:eval:merchants[dev]' (lists errors)"
    task :merchants, %i[ set ] => :environment do |_, args|
      exit Evaluation::Gate.run(set: args[:set] || "golden")
    end
  end
end
