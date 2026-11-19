module Api
  module V1
    class SessionsController < BaseController
      allow_unauthenticated_access only: :create
      rate_limit to: 10, within: 3.minutes, only: :create,
        with: -> { render_error :too_many_requests, "rate_limited", "Too many attempts. Try again later." }

      def create
        credentials = params.expect(session: %i[ email_address password ])
        if (user = User.authenticate_by(credentials))
          start_new_session_for user
          render status: :created, json: MeController.payload(user)
        else
          render_error :unauthorized, "invalid_credentials", "Wrong email address or password."
        end
      end

      def destroy
        terminate_session
        head :no_content
      end
    end
  end
end
