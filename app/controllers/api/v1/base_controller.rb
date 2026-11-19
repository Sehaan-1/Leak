module Api
  module V1
    # JSON API for the SPA. Same-origin cookie session (Rails auth generator)
    # plus Rails' CSRF token on writes; no tokens in localStorage.
    class BaseController < ApplicationController
      rescue_from ActiveRecord::RecordNotFound do
        render_error :not_found, "not_found", "Not found."
      end

      rescue_from ActionController::ParameterMissing do |error|
        render_error :bad_request, "bad_request", error.message
      end

      rescue_from ActionController::InvalidAuthenticityToken do
        render_error :unprocessable_content, "invalid_csrf_token", "Missing or invalid CSRF token."
      end

      private
        def request_authentication
          render_error :unauthorized, "unauthorized", "Sign in to continue."
        end

        def render_error(status, code, message)
          render status: status, json: { error: { code: code, message: message } }
        end

        def current_household
          Current.household
        end
    end
  end
end
