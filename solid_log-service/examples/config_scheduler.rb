# Example: SolidLog Service with Built-in Scheduler (DEFAULT/RECOMMENDED)
# Place this in: config/solid_log_service.rb

SolidLog::Service.configure do |config|
  # Database connection
  config.database_url = ENV['DATABASE_URL'] || 'sqlite3:///app/storage/production_log.sqlite'

  # Job processing mode
  config.job_mode = :scheduler  # Built-in scheduler (default)

  # Scheduler intervals (only used when job_mode = :scheduler)
  config.parser_interval = 10          # Parse logs every 10 seconds
  config.cache_cleanup_interval = 3600 # Clean cache every hour (3600 seconds)
  config.retention_hour = 2            # Run retention job at 2 AM
  config.field_analysis_hour = 3       # Run field analysis at 3 AM

  # Retention policies
  config.retention_days = 30           # Keep regular logs for 30 days
  config.error_retention_days = 90     # Keep errors for 90 days

  # Parsing & ingestion
  config.max_batch_size = 1000         # Max logs per batch insert
  config.parser_concurrency = 5        # Parallel parser workers (not used in scheduler mode)

  # Performance
  config.facet_cache_ttl = 5.minutes   # Cache filter options for 5 min

  # Field promotion
  config.auto_promote_fields = false   # Auto-promote hot fields
  config.field_promotion_threshold = 1000  # Usage count for auto-promotion

  # Server settings
  config.bind = '0.0.0.0'
  config.port = 3001

  # CORS (optional)
  config.cors_origins = ['*']  # Allow all origins, or specify domains
end

# Usage:
# bundle exec solid_log_service
# or via Kamal:
#   service: bundle exec solid_log_service
