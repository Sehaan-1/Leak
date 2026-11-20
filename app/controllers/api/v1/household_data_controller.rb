module Api
  module V1
    # The "Your data" screen: what Leak holds for the household, and
    # "Delete my data", which erases all of it but keeps the sign-in.
    class HouseholdDataController < BaseController
      def show
        render json: payload(current_household.data_counts)
      end

      def destroy
        deleted = current_household.erase_data!
        render json: { deleted: deleted }
      end

      private
        def payload(counts)
          { counts: counts, demo_expires_at: current_household.demo_expires_at&.iso8601 }
        end
    end
  end
end
