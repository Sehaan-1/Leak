namespace :leak do
  desc "Re-run recurring-charge detection for a household: bin/rails 'leak:detect[user@example.com]'"
  task :detect, %i[ email ] => :environment do |_, args|
    household = User.find_by!(email_address: args.fetch(:email)).household
    result = Detection::Run.new(household: household).call
    puts "✓ #{result.series.size} recurring series (#{result.series.count(&:flagged)} flagged), " \
      "#{result.findings.size} findings: #{result.findings.map(&:kind).tally.map { |kind, n| "#{kind} #{n}" }.join(", ")}"
  end
end
