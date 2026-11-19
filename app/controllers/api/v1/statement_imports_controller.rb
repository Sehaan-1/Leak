module Api
  module V1
    # Upload a bank statement PDF. Processed synchronously: a statement is a
    # few pages and pdftotext takes milliseconds. The file is read from the
    # request's tempfile and never stored.
    class StatementImportsController < BaseController
      def index
        imports = current_household.statement_imports.includes(bank_account: :account).order(created_at: :desc).limit(50)
        render json: { statement_imports: imports.map { |import| self.class.payload(import) } }
      end

      def create
        file = params.require(:file)
        unless file.respond_to?(:tempfile)
          return render_error :bad_request, "bad_request", "Attach the statement as a file."
        end

        existing_ids = current_household.statement_imports.ids
        import = Statements::Importer.import_pdf(
          household: current_household, path: file.tempfile.path,
          filename: file.original_filename, password: params[:password].presence
        )
        status = if import.rejected? then :unprocessable_content
        elsif existing_ids.include?(import.id) then :ok
        else :created
        end
        render status: status, json: self.class.payload(import)
      end

      def self.payload(import)
        bank_account = import.bank_account
        {
          id: import.id,
          status: import.status,
          filename: import.filename,
          period_from: import.period_from&.iso8601,
          period_to: import.period_to&.iso8601,
          opening_balance_paise: import.opening_balance_paise,
          closing_balance_paise: import.closing_balance_paise,
          rows_count: import.rows_count,
          new_rows_count: import.new_rows_count,
          error: import.rejected? ? { message: import.error_message, line: import.error_line } : nil,
          bank_account: bank_account && { id: bank_account.id, name: bank_account.display_name },
          created_at: import.created_at.iso8601
        }
      end
    end
  end
end
