Rails.application.routes.draw do
  # HTML sign-in and password reset from the Rails 8 authentication generator.
  resource :session
  resources :passwords, param: :token

  # JSON API consumed by the SPA. Contract: openapi/openapi.yaml.
  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      resource :session, only: %i[ create destroy ]
      resource :me, only: :show, controller: :me
      resources :accounts, only: :index
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#show"
end
