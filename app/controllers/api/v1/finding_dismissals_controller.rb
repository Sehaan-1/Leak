module Api
  module V1
    # Mark a finding as fine, or take that back. Keyed on a ledger row so it
    # survives detection re-runs (FindingDismissal).
    class FindingDismissalsController < BaseController
      def create
        finding = find_finding
        current_household.finding_dismissals.find_or_create_by!(kind: finding.kind,
          bank_transaction_id: finding.anchor_transaction_id)
        render status: :created, json: FindingsController.payload(finding, dismissed: true)
      end

      def destroy
        finding = find_finding
        current_household.finding_dismissals
          .where(kind: finding.kind, bank_transaction_id: finding.evidence_transaction_ids).delete_all
        render json: FindingsController.payload(finding, dismissed: false)
      end

      private
        def find_finding
          current_household.findings.includes(*FindingsController.preloads).find(params[:finding_id])
        end
    end
  end
end
