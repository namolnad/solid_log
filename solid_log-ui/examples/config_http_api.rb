# Example: SolidLog UI with HTTP API Mode (Remote Service)
# Place this in: config/initializers/solid_log_ui.rb
#
# Use this when the UI and service run on different hosts/containers

SolidLog::UI.configure do |config|
  # Data access mode
  config.mode = :http_api  # Query via HTTP API

  # Service connection
  config.service_url = ENV['SOLIDLOG_SERVICE_URL'] || 'http://solidlog-service:3001'
  config.service_token = ENV['SOLIDLOG_SERVICE_TOKEN']

  # Controller inheritance
  config.base_controller = "ApplicationController"

  # Authentication
  config.authentication_method = :custom  # Handled by ApplicationController

  # UI settings
  config.websocket_enabled = false        # WebSocket not supported in HTTP API mode
  config.stream_view_style = :compact
  config.per_page = 100
  config.facet_cache_ttl = 1.minute
end

# Mount in routes (config/routes.rb):
# mount SolidLog::UI::Engine => "/admin/logs"

# Your ApplicationController should handle authentication:
# class ApplicationController < ActionController::Base
#   before_action :authenticate_user!
#
#   def authenticate_user!
#     redirect_to login_path unless current_user
#   end
#
#   def current_user
#     @current_user ||= User.find_by(id: session[:user_id])
#   end
# end

# Environment variables:
# SOLIDLOG_SERVICE_URL=http://logs.example.com:3001
# SOLIDLOG_SERVICE_TOKEN=slk_abc123...  # From service: rails solid_log:create_token

# Benefits of HTTP API mode:
# - UI can run in separate application
# - Service can be on different server/network
# - Multiple UIs can query same service
# - Service can scale independently
