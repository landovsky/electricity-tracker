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
  # AUTHENTICATION (Magic Link + SMS OTP)
  # =============================================================================
  get "prihlaseni", to: "sessions#new", as: :login
  post "prihlaseni", to: "sessions#create"
  get "prihlaseni/email_odeslan", to: "sessions#email_sent", as: :email_sent
  post "prihlaseni/sms", to: "sessions#create_sms", as: :login_sms
  get "prihlaseni/overeni", to: "sessions#otp_form", as: :otp_form
  post "prihlaseni/overeni", to: "sessions#verify_otp", as: :verify_otp
  get "auth/:token", to: "sessions#verify", as: :auth_verify
  delete "odhlaseni", to: "sessions#destroy", as: :logout

  # Onboarding (name input for new self-registered users)
  get "uvod", to: "onboarding#show", as: :onboarding
  patch "uvod", to: "onboarding#update"

  # =============================================================================
  # MAIN APPLICATION
  # =============================================================================

  # Root / Dashboard (S1 - Main Screen)
  root "dashboard#index"

  # Stays (Check-in / Check-out)
  resources :pobyty, controller: "stays", only: [ :create ], as: :stays do
    member do
      patch :check_out
    end
  end

  # Manual Consumption Entries
  resources :rucni_spotreba, controller: "manual_consumption_entries", only: [ :create ], as: :manual_consumption_entries

  # Consumption Report (S2)
  get "prehled-spotreby", to: "consumption_reports#index", as: :consumption_reports

  # Meter Reading Events
  resources :odecty, controller: "meter_reading_events", only: [ :destroy ], as: :meter_reading_events

  # Readings History (S3)
  get "historie-odectu", to: "readings_history#index", as: :readings_history

  # Visitors
  resources :navstevnici, controller: "visitors", as: :visitors do
    member do
      patch :archive
    end
  end

  # Properties (admin-only management)
  resources :nemovitosti, controller: "properties", except: [ :destroy ], as: :properties do
    member do
      patch :archive
    end
  end

  # Users (admin-only management)
  resources :uzivatele, controller: "users", except: [ :destroy ], as: :users do
    member do
      patch :archive
    end
  end

  # =============================================================================
  # ADMIN
  # =============================================================================
  namespace :admin do
    post "migrace/xls", to: "migrations#xls", as: :xls_migration
  end
end
