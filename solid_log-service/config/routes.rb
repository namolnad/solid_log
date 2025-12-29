SolidLog::Service::Engine.routes.draw do
  namespace :api do
    namespace :v1 do
      # Ingestion
      post 'ingest', to: 'ingest#create'

      # Queries
      resources :entries, only: [:index, :show]
      post 'search', to: 'search#create'

      # Facets
      get 'facets', to: 'facets#index'
      get 'facets/all', to: 'facets#all', as: :all_facets

      # Timelines
      get 'timelines/request/:request_id', to: 'timelines#show_request', as: :timeline_request
      get 'timelines/job/:job_id', to: 'timelines#show_job', as: :timeline_job

      # Health
      get 'health', to: 'health#show'
    end
  end

  # Root health check
  get '/health', to: 'api/v1/health#show'
end
