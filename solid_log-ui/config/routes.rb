SolidLog::UI::Engine.routes.draw do
  # Root - redirect to streams
  root to: redirect("/logs/streams")

  # Dashboard
  get "dashboard", to: "dashboard#index"

  # Main log viewing
  resources :streams, only: [:index]
  resources :entries, only: [:index, :show]

  # Timeline routes for correlation
  get "timelines/request/:request_id", to: "timelines#show_request", as: :request_timeline
  get "timelines/job/:job_id", to: "timelines#show_job", as: :job_timeline

  # Field management
  resources :fields, only: [:index, :destroy] do
    member do
      post :promote
      post :demote
      patch :update_filter_type
    end
  end

  # Token management
  resources :tokens, only: [:index, :new, :create, :destroy]
end
