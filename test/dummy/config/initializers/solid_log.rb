# SolidLog Configuration
SolidLog.configure do |config|
  # Maximum number of log entries to ingest in a single batch
  config.max_batch_size = 1000

  # Client configuration (for sending logs from this app to a SolidLog instance)
  # config.client_token = ENV['SOLID_LOG_TOKEN']
  # config.ingestion_url = 'https://logs.example.com/solid_log/api/v1/ingest'

  # Future features (not yet implemented):
  # config.retention_days = 30              # Auto-delete logs older than X days
  # config.error_retention_days = 90        # Keep errors longer
  # config.auto_promote_fields = false      # Auto-promote high-usage fields
  # config.field_promotion_threshold = 1000 # Usage threshold for auto-promotion
  # config.facet_cache_ttl = 5.minutes      # Cache filter dropdown values
  # config.parser_concurrency = 5           # Concurrent parser workers
end

Rails.application.configure do
  # Enhanced logging with useful tags for debugging and monitoring
  config.log_tags = [
    :request_id,     # Track requests across services
    :subdomain,      # Useful for multi-tenant apps
    lambda { |req| "ip:#{req.remote_ip}" },           # Track user IP
    lambda { |req| "user:#{req.session[:user_id]}" }, # Track authenticated user
    lambda { |req| "method:#{req.method}" },          # HTTP method
    lambda { |req| req.path.start_with?("/admin") ? "admin" : "app" } # Admin vs app routes
  ]

  # Set log level based on environment
  config.log_level = Rails.env.production? ? :info : :debug

  # Format timestamps in logs
  config.time_zone = "UTC"

  # Reduce logging noise in development
  if Rails.env.development?
    # Quiet asset pipeline logs (if assets are enabled)
    config.assets.quiet = true if config.respond_to?(:assets)

    # Consider setting log level to info to reduce debug noise
    # config.log_level = :info
  end
end
