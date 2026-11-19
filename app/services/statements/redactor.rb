module Statements
  # Turns statement text into a shape-only copy that is safe to share when
  # reporting a parsing problem: letters become x/X, digits become 9, and
  # spacing and punctuation are kept, so columns line up exactly as before.
  # Generic column and banking words stay readable.
  module Redactor
    KEEP = %w[
      Value Txn Post Date Details Description Ref No No. Cheque Chq Debit Credit Balance
      Statement From to of Page Account Number IFSC Code Clear Uncleared Amount Branch
      Opening Closing Total CR DR TFR UPI NEFT IMPS RTGS DEP WDL ATM POS ACH NACH INR
      Interest Rate Limit Lien Drawing Power MOD Bal Currency Product Status Monthly Avg
      Name Email Phone CIF MICR Nominee Open OPEN Summary STATEMENT OF ACCOUNT Welcome As on
    ].to_set.freeze

    module_function

    def redact(text)
      text.gsub(/[[:alnum:]]+/) do |word|
        KEEP.include?(word) ? word : word.gsub(/[[:upper:]]/, "X").gsub(/[[:lower:]]/, "x").gsub(/\d/, "9")
      end
    end
  end
end
