# SolidLog Configuration for Test App
# This demonstrates a monolith setup with all 3 gems

# Configure SolidLog models to use the :log database (defined in database.yml)
# This is done in the host app instead of in the gem
SolidLog::ApplicationRecord.connects_to database: { writing: :log, reading: :log }

# Core configuration (for models and services)
SolidLog::Core.configure do |config|
  config.retention_days = 30
  config.error_retention_days = 90
  config.max_batch_size = 1000
  config.live_tail_mode = :websocket
  config.parser_concurrency = 5
  config.auto_promote_fields = false
  config.field_promotion_threshold = 1000
end

# Service configuration (for background jobs and API)
if defined?(SolidLog::Service)
  SolidLog::Service.configure do |config|
    # Use built-in scheduler for background jobs
    config.job_mode = :scheduler
    config.parser_interval = 10  # seconds
    config.cache_cleanup_interval = 1.hour
    config.retention_hour = 2  # 2 AM
    config.field_analysis_hour = 3  # 3 AM

    # Disable websockets for simplicity
    config.websocket_enabled = false

    # No CORS needed for monolith
    config.cors_origins = []
  end
end

# UI configuration
SolidLog::UI.configure do |config|
  # Use direct DB mode (fastest for monolith)
  config.mode = :direct_db

  # Inherit from ApplicationController for auth
  config.base_controller = "ApplicationController"

  # No authentication for test app
  config.authentication_method = :none

  # UI settings
  config.websocket_enabled = true
  config.stream_view_style = :compact
  config.facet_cache_ttl = 1.minute
  config.per_page = 100
end

# Start the service scheduler after initialization
if defined?(SolidLog::Service)
  Rails.application.config.after_initialize do
    SolidLog::Service::JobProcessor.setup
    Rails.logger.info "SolidLog: Background job processor started"
  end

  # Gracefully stop scheduler on shutdown (SIGTERM, SIGINT)
  trap('SIGTERM') do
    Rails.logger.info "SolidLog: Received SIGTERM, stopping scheduler..."
    SolidLog::Service::JobProcessor.stop
    exit
  end

  trap('SIGINT') do
    Rails.logger.info "SolidLog: Received SIGINT, stopping scheduler..."
    SolidLog::Service::JobProcessor.stop
    exit
  end
end
