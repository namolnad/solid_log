# Example: SolidLog UI with Direct Database Access
# Place this in: config/initializers/solid_log_ui.rb
#
# Use this when UI and service share the same database (fastest option)

SolidLog::UI.configure do |config|
  # Data access mode
  config.mode = :direct_db  # Query database directly

  # Controller inheritance - inherit from your app's base controller
  config.base_controller = "ApplicationController"

  # Authentication
  config.authentication_method = :custom  # Handled by ApplicationController

  # UI settings
  config.websocket_enabled = true         # Enable live tail
  config.stream_view_style = :compact     # or :expanded
  config.per_page = 100                   # Logs per page
  config.facet_cache_ttl = 1.minute       # Cache filter options
end

# Mount in routes (config/routes.rb):
# mount SolidLog::UI::Engine => "/admin/logs"

# Database configuration (config/database.yml):
# production:
#   primary:
#     adapter: sqlite3
#     database: storage/production.sqlite3
#   log:
#     adapter: sqlite3
#     database: storage/production_log.sqlite3  # Shared with service
#     migrations_paths: db/log_migrate

# Your ApplicationController should handle authentication:
# class ApplicationController < ActionController::Base
#   before_action :authenticate_user!
#
#   def current_user
#     @current_user ||= User.find_by(id: session[:user_id])
#   end
# end

# Access at: http://yourapp.com/admin/logs
