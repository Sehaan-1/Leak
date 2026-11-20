module Api
  module V1
    # What detection flagged, each with its evidence: the series
    # and, for a price increase, the first charge at the new price. Price
    # increases and duplicates first, then subscriptions by monthly cost.
    class FindingsController < BaseController
      KIND_ORDER = %w[ price_increase duplicate subscription ].freeze

      def index
        findings = current_household.findings.includes(*self.class.preloads).to_a
          .sort_by { |finding| [ KIND_ORDER.index(finding.kind), -finding.monthly_cost_paise, finding.id ] }
        dismissed = FindingDismissal.dismissed_ids(current_household, findings)
        subscriptions = findings.select { |finding| finding.kind_subscription? && finding.recurring_series.status_active? }

        render json: {
          findings: findings.map { |finding| self.class.payload(finding, dismissed: dismissed.include?(finding.id)) },
          monthly_total_paise: subscriptions.sum(&:monthly_cost_paise),
          subscriptions_count: subscriptions.size
        }
      end

      def self.preloads
        [ :step_transaction, { recurring_series: %i[ merchant series_charges ], related_series: :merchant } ]
      end

      def self.payload(finding, dismissed:)
        step = finding.step_transaction
        {
          id: finding.id,
          kind: finding.kind,
          dismissed: dismissed,
          amount_paise: finding.amount_paise,
          monthly_cost_paise: finding.monthly_cost_paise,
          previous_amount_paise: finding.previous_amount_paise,
          step_charge: step && { id: step.id, posted_on: step.posted_on.iso8601, charged_paise: -step.amount_paise },
          series: RecurringSeriesController.summary(finding.recurring_series),
          related_series: finding.related_series && RecurringSeriesController.summary(finding.related_series)
        }
      end
    end
  end
end
