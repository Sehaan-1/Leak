# Placeholder landing page after sign-in. The React SPA shell replaces this
# in a later slice (Rails will serve it from a layout with the CSRF token).
class HomeController < ApplicationController
  def show
    @household = Current.household
  end
end
