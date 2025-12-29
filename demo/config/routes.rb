Rails.application.routes.draw do
  # Health check endpoint
  get "up", to: "rails/health#show", as: :rails_health_check

  # Action Cable endpoint
  mount ActionCable.server => "/cable"

  # Root path - log generator
  root "log_generator#index"

  # Log generator routes
  resources :log_generator, only: [:index] do
    collection do
      post :generate
      post :generate_batch
      post :trigger_job
    end
  end

  # Mount SolidLog UI at /logs
  mount SolidLog::UI::Engine => "/logs"
end
