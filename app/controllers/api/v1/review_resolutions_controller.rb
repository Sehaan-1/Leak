module Api
  module V1
    # The household names the counterparty of a row in review. Naming a
    # merchant also teaches the rules (Merchants::ManualResolution).
    class ReviewResolutionsController < BaseController
      def create
        txn = current_household.bank_transactions.needs_review.find(params[:review_item_id])
        counterparty = params.require(:counterparty).to_s
        unless BankTransaction.counterparties.key?(counterparty)
          return render_error :unprocessable_content, "invalid_counterparty", "Choose a merchant, a person, the bank or cash."
        end

        merchant = Merchant.find_by(id: params[:merchant_id]) if counterparty == "merchant"
        if counterparty == "merchant" && merchant.nil?
          return render_error :unprocessable_content, "merchant_required", "Choose which merchant this was."
        end

        outcome = Merchants::ManualResolution.new(household: current_household)
          .call(txn, counterparty: counterparty, merchant: merchant)
        render json: {
          review_item_id: txn.id,
          counterparty: counterparty,
          merchant: merchant && MerchantsController.payload(merchant),
          learned: outcome.learned && { kind: outcome.learned.kind, pattern: outcome.learned.pattern },
          also_resolved_count: outcome.also_resolved
        }
      end
    end
  end
end
