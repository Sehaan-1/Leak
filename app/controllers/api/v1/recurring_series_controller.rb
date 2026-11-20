module Api
  module V1
    # One recurring series with the ledger rows behind it, oldest first, and
    # what was flagged about it. Series are rebuilt on every detection run,
    # so an id from an earlier run answers 404.
    class RecurringSeriesController < BaseController
      def show
        series = current_household.recurring_series.includes(:merchant, series_charges: :bank_transaction).find(params[:id])
        findings = current_household.findings.where(recurring_series: series).includes(*FindingsController.preloads).to_a
        dismissed = FindingDismissal.dismissed_ids(current_household, findings)
        step_ids = findings.filter_map(&:step_transaction_id).to_set
        charges = series.series_charges.sort_by { |charge| [ charge.bank_transaction.posted_on, charge.bank_transaction_id ] }

        render json: self.class.summary(series).merge(
          flagged: series.flagged,
          findings: findings.sort_by { |finding| FindingsController::KIND_ORDER.index(finding.kind) }
            .map { |finding| FindingsController.payload(finding, dismissed: dismissed.include?(finding.id)) },
          charges: charges.map { |charge| charge_payload(charge, price_step: step_ids.include?(charge.bank_transaction_id)) }
        )
      end

      def self.summary(series)
        {
          id: series.id,
          merchant: MerchantsController.payload(series.merchant),
          cadence: series.cadence,
          status: series.status,
          amount_paise: series.amount_paise,
          monthly_cost_paise: series.monthly_cost_paise,
          first_charged_on: series.first_charged_on.iso8601,
          last_charged_on: series.last_charged_on.iso8601,
          next_expected_on: series.next_expected_on.iso8601,
          charges_count: series.charges_count
        }
      end

      private
        def charge_payload(charge, price_step:)
          txn = charge.bank_transaction
          {
            id: txn.id,
            posted_on: txn.posted_on.iso8601,
            charged_paise: -txn.amount_paise,
            level: charge.level,
            price_step: price_step,
            narration: txn.narration
          }
        end
    end
  end
end
