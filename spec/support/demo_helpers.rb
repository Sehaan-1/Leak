# The demo household's year of statements (lib/synthetic/demo_statement.rb),
# imported and run through detection: realistic data with known findings.
module DemoHelpers
  def import_demo!(household)
    Merchants::Catalogue.sync!
    Demo.populate!(household)
  end

  # [[kind, merchant slug], ...] of a household's findings.
  def finding_labels(household)
    household.findings.includes(recurring_series: :merchant).map { |finding| [ finding.kind, finding.recurring_series.merchant.slug ] }
  end

  def review_row(household, text)
    key = text.delete(" ")
    household.bank_transactions.needs_review.find { |txn| txn.narration.delete(" ").include?(key) } or
      raise "no #{text} row in review"
  end
end
