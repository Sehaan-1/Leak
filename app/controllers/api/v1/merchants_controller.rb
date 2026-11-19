module Api
  module V1
    # The merchant catalogue (config/merchants.yml), for the review queue's
    # picker. Global reference data: the same for every household.
    class MerchantsController < BaseController
      def index
        merchants = Merchant.all.sort_by { |merchant| merchant.name.downcase }
        render json: { merchants: merchants.map { |merchant| self.class.payload(merchant) } }
      end

      def self.payload(merchant)
        { id: merchant.id, slug: merchant.slug, name: merchant.name, category: merchant.category }
      end
    end
  end
end
