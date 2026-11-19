module Detection
  # Runs Detection::Engine over a household's merchant transactions and
  # replaces its recurring series and findings with the result:
  #
  #   Detection::Run.new(household: household).call  # => Detection::Engine::Result
  #
  # "Now" is the household's latest transaction date, so a series is active
  # if it charged when expected up to the end of its last statement, however
  # old that statement is.
  class Run
    def initialize(household:, as_of: nil)
      @household = household
      @as_of = as_of
    end

    def call
      rows = @household.bank_transactions.joins(:merchant).where(counterparty: "merchant")
        .pluck(:id, :merchant_id, "merchants.slug", "merchants.category", :posted_on, :amount_paise)
      merchant_ids = rows.to_h { |row| [ row[2], row[1] ] }
      txns = rows.map { |id, _, slug, category, on, amount| Txn.new(id, slug, category, on, amount) }
      as_of = @as_of || @household.bank_transactions.maximum(:posted_on) || Date.current
      result = Engine.new(as_of: as_of).call(txns)

      ApplicationRecord.transaction do
        @household.findings.delete_all
        @household.recurring_series.delete_all
        saved = result.series.to_h { |series| [ series, save_series(series, merchant_ids.fetch(series.merchant)) ] }
        result.findings.each { |finding| save_finding(finding, saved) }
      end
      result
    end

    private
      def save_series(series, merchant_id)
        record = @household.recurring_series.create!(
          merchant_id: merchant_id, cadence: series.cadence.name, status: series.status, flagged: series.flagged,
          amount_paise: series.amount_paise, monthly_cost_paise: series.monthly_cost_paise,
          first_charged_on: series.first_charged_on, last_charged_on: series.last_charged_on,
          next_expected_on: series.next_expected_on, charges_count: series.charges.size
        )
        rows = series.levels.each_with_index.flat_map do |charges, level|
          charges.map do |charge|
            { household_id: @household.id, recurring_series_id: record.id, bank_transaction_id: charge.id, level: level }
          end
        end
        RecurringSeriesCharge.insert_all!(rows)
        record
      end

      def save_finding(finding, saved)
        @household.findings.create!(
          recurring_series: saved.fetch(finding.series), kind: finding.kind,
          amount_paise: finding.amount_paise, monthly_cost_paise: finding.monthly_cost_paise,
          previous_amount_paise: finding.previous_amount_paise, step_transaction_id: finding.step_charge&.id,
          related_series: finding.related && saved.fetch(finding.related)
        )
      end
  end
end
