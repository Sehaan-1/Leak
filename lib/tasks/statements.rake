namespace :leak do
  desc "Import a bank statement PDF: bin/rails 'leak:import[path/to/statement.pdf,user@example.com]' (PDF_PASSWORD=... if protected)"
  task :import, %i[ path email ] => :environment do |_, args|
    user = User.find_by!(email_address: args.fetch(:email))
    started_at = Time.current
    import = Statements::Importer.import_pdf(
      household: user.household, path: args.fetch(:path),
      filename: File.basename(args.fetch(:path)), password: ENV["PDF_PASSWORD"]
    )

    if import.rejected?
      warn "✗ Rejected: #{import.error_message}#{" (text line #{import.error_line})" if import.error_line}"
      exit 1
    end

    if import.created_at < started_at
      puts "= Already imported on #{import.created_at.to_date} (#{import.filename}); nothing changed."
      next
    end

    puts "✓ Statement ties: #{import.rows_count} rows, #{import.new_rows_count} new, " \
      "#{import.period_from} to #{import.period_to}, closing #{Paise.format(import.closing_balance_paise)}"
    if (rec = import.bank_account.reconciliation) && !rec[:difference_paise].zero?
      puts "! Ledger differs from the latest statement by #{Paise.format(rec[:difference_paise])}: a statement may be missing."
    end
  end

  desc "Print a redacted, shape-only copy of a statement's text, safe to share: bin/rails 'leak:redact[path/to/statement.pdf]'"
  task :redact, %i[ path ] => :environment do |_, args|
    puts Statements::Redactor.redact(Statements::PdfText.extract(args.fetch(:path), password: ENV["PDF_PASSWORD"]))
  end
end
