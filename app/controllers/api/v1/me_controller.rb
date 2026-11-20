module Api
  module V1
    class MeController < BaseController
      def self.payload(user)
        {
          user: { id: user.id, email_address: user.email_address },
          household: { id: user.household.id, name: user.household.name,
                       demo_expires_at: user.household.demo_expires_at&.iso8601 }
        }
      end

      def show
        render json: self.class.payload(Current.user)
      end
    end
  end
end
