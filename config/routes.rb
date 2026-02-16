Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Letter opener for email preview in development
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # =============================================================================
  # AUTHENTICATION (Magic Link)
  # =============================================================================
  # Magic link authentication flow:
  # 1. User requests magic link (GET /login, POST /login)
  # 2. User clicks link from email (GET /auth/:token)
  # 3. User logs out (DELETE /logout)

  get "login", to: "sessions#new", as: :login
  post "login", to: "sessions#create"
  get "auth/:token", to: "sessions#verify", as: :auth_verify
  delete "logout", to: "sessions#destroy", as: :logout

  # =============================================================================
  # MAIN APPLICATION
  # =============================================================================

  # Root / Dashboard (S1 - Main Screen)
  # Combined view: house status, action forms (check-in/out, manual entry), recent activity
  root "dashboard#index"

  # Stays (Check-in / Check-out)
  # Check-in creates a new stay, check-out closes an existing stay
  # Both require meter readings
  resources :stays, only: [ :create ] do
    member do
      # Custom action for check-out (closes the stay)
      # PATCH /stays/:id/check_out
      patch :check_out
    end
  end

  # Manual Consumption Entries
  # Direct kWh attribution (e.g., EV charging) without a formal stay
  resources :manual_consumption_entries, only: [ :create ]

  # Consumption Report (S2)
  # Summary view showing kWh breakdown per visitor for a date range
  # Single index action with date range params (year, start_date, end_date)
  get "consumption_reports", to: "consumption_reports#index", as: :consumption_reports

  # Readings History (S3)
  # Chronological log of all meter reading events and manual entries
  # Filterable by visitor and date range
  get "readings_history", to: "readings_history#index", as: :readings_history

  # Visitors
  # Full CRUD for visitor management
  resources :visitors do
    member do
      # Soft delete / archive a visitor
      # PATCH /visitors/:id/archive
      patch :archive
    end
  end

  # =============================================================================
  # ADMIN NAMESPACE (Future Extension Point)
  # =============================================================================
  # Admin operations (corrections, validation overrides, audit trail review)
  # v1: JSON API endpoints and Rails console only
  # Future: Admin UI for corrections, user management, etc.
  #
  # namespace :admin do
  #   resources :meter_reading_events, only: [:edit, :update, :destroy]
  #   resources :stays, only: [:edit, :update]
  #   resources :manual_consumption_entries, only: [:edit, :update, :destroy]
  #   resources :users
  # end
end
