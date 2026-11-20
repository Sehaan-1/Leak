module Api
  module V1
    # "Try it with made-up data" on the public demo (LEAK_DEMO=1): a fresh
    # household of synthetic data, signed in, deleted after a day. Not found
    # on a private instance.
    class DemoSessionsController < BaseController
      allow_unauthenticated_access only: :create
      before_action :require_demo
      rate_limit to: 5, within: 10.minutes, only: :create,
        with: -> { render_error :too_many_requests, "rate_limited", "Too many demo accounts from here. Try again later." }

      def create
        user = Demo.create_user!
        start_new_session_for user
        render status: :created, json: MeController.payload(user)
      end

      private
        def require_demo
          render_error :not_found, "not_found", "Not found." unless Demo.enabled?
        end
    end
  end
end
