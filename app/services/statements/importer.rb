require "digest"

module Statements
  # Imports a statement into a household's ledger.
  #
  #   Statements::Importer.import_pdf(household:, path:, filename:, password: nil)
  #     # => StatementImport (status "imported" or "rejected")
  #
  # Idempotent: re-importing the same file returns the earlier import, and
  # lines already in the ledger (re-downloads, overlapping periods) are
  # skipped by fingerprint. Nothing is written unless the whole statement
  # reconciles. The PDF itself is never stored, only its SHA-256.
  class Importer
    def self.import_pdf(household:, path:, filename:, password: nil)
      sha = Digest::SHA256.file(path).hexdigest
      existing = household.statement_imports.imported.find_by(file_sha256: sha)
      return existing if existing

      new(household: household, filename: filename, file_sha256: sha)
        .import { PdfText.extract(path, password: password) }
    end

    def self.import_text(household:, text:, filename:)
      sha = Digest::SHA256.hexdigest(text)
      existing = household.statement_imports.imported.find_by(file_sha256: sha)
      return existing if existing

      new(household: household, filename: filename, file_sha256: sha).import { text }
    end

    def initialize(household:, filename:, file_sha256:)
      @household = household
      @filename = filename.to_s.first(255).presence || "statement.pdf"
      @file_sha256 = file_sha256
    end

    def import
      text = yield
      statement = Statements.parser_for(text).parse(text)
      opening = Reconciler.check!(statement)
      post(statement, opening).tap { Merchants::LlmResolutionJob.enqueue_for(household) }
    rescue Statements::Error => error
      reject(error)
    end

    private
      attr_reader :household

      def post(statement, opening)
        ApplicationRecord.transaction do
          bank_account = BankAccount.for_statement!(household, statement)
          bank_account.lock!
          check_conflicts!(bank_account, statement, opening)

          import = household.statement_imports.create!(
            bank_account: bank_account, status: "imported", filename: @filename, file_sha256: @file_sha256,
            period_from: statement.period_from, period_to: statement.period_to,
            opening_balance_paise: opening, closing_balance_paise: statement.rows.last.balance_paise,
            rows_count: statement.rows.size
          )
          new_rows = statement.rows.each_with_index.count { |row, position| post_row(bank_account, import, row, position) }
          import.update!(new_rows_count: new_rows)
          bank_account.sync_opening_balance!
          import
        end
      rescue ActiveRecord::RecordNotUnique
        # A concurrent import of the same file won the race.
        household.statement_imports.imported.find_by!(file_sha256: @file_sha256)
      end

      def post_row(bank_account, import, row, position)
        fingerprint = Fingerprint.for(bank_account, row)
        return false if household.bank_transactions.exists?(fingerprint: fingerprint)

        amount = row.amount_paise
        entry = Ledger.post!(
          household: household, occurred_on: row.posted_on,
          memo: "#{amount.positive? ? "Credit" : "Debit"} · #{bank_account.display_name}",
          lines: [ [ bank_account.account, amount ], [ household.suspense_account, -amount ] ]
        )
        txn = household.bank_transactions.new(
          bank_account: bank_account, statement_import: import, journal_entry: entry,
          posted_on: row.posted_on, value_on: row.value_on, narration: row.narration, ref: row.ref,
          amount_paise: amount, balance_after_paise: row.balance_paise,
          fingerprint: fingerprint, position: position
        )
        txn.apply_resolution(resolver.resolve(row.narration, amount_paise: amount))
        txn.save!
        true
      end

      # Rules resolve rows as they're posted; rows they can't decide go to
      # review, and to the LLM resolver once the import commits.
      def resolver
        @resolver ||= Merchants::Resolver.new(household: household)
      end

      # Two statements starting on the same day begin with the same
      # transaction, so they must agree on the opening balance.
      def check_conflicts!(bank_account, statement, opening)
        clash = bank_account.statement_imports.imported
          .where(period_from: statement.period_from).where.not(opening_balance_paise: opening).first
        return unless clash

        raise Conflict, "This statement's opening balance (#{Paise.format(opening)}) disagrees with " \
          "#{clash.filename} (#{Paise.format(clash.opening_balance_paise)}), which starts on the same day."
      end

      def reject(error)
        household.statement_imports.create!(
          status: "rejected", filename: @filename, file_sha256: @file_sha256,
          error_message: error.message, error_line: error.line_no
        )
      end
  end
end
