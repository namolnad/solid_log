SolidLog::Engine.routes.draw do
  # API routes for log ingestion
  namespace :api do
    namespace :v1 do
      post "ingest", to: "ingest#create"
    end
  end

  # UI routes
  root to: "dashboard#index", as: :solid_log
  get "dashboard", to: "dashboard#index"
  resources :streams, only: [ :index ]
  resources :entries, only: [ :index, :show ]

  # Timeline routes for correlation
  get "timelines/request/:request_id", to: "timelines#request", as: :request_timeline
  get "timelines/job/:job_id", to: "timelines#job", as: :job_timeline

  # Field management
  resources :fields, only: [ :index, :destroy ] do
    member do
      post :promote
      post :demote
      patch :update_filter_type
    end
  end

  # Token management
  resources :tokens, only: [ :index, :new, :create, :destroy ]
end
