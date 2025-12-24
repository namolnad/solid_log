# SolidLog Configuration
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

# Configure SolidLog
SolidLog.configure do |config|
  config.retention_days = 30
  config.error_retention_days = 90
  config.max_batch_size = 1000
  config.parser_concurrency = 5
  config.facet_cache_ttl = 5.minutes
  config.authentication_method = :basic
  config.ui_enabled = true
  config.auto_promote_fields = false
  config.field_promotion_threshold = 1000
end
