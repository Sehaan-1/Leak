# Serves the single-page app's HTML shell. Rendering it from Rails (rather
# than a static index.html) embeds the CSRF token the SPA sends on writes.
# The SPA itself decides whether to show sign-in, via GET /api/v1/me.
class SpaController < ApplicationController
  allow_unauthenticated_access

  def show
    render layout: false
  end
end
