# Example: SolidLog Service with ActiveJob Integration
# Place this in: config/solid_log_service.rb
#
# Use this when you want to leverage your host app's existing job backend
# (Solid Queue, Sidekiq, etc.)

SolidLog::Service.configure do |config|
  # Database connection (shared with main app)
  config.database_url = ENV['DATABASE_URL']

  # Job processing mode
  config.job_mode = :active_job  # Use host app's job backend

  # Retention policies
  config.retention_days = 30
  config.error_retention_days = 90

  # Other settings...
  config.max_batch_size = 1000
  config.facet_cache_ttl = 5.minutes
end

# Then in your host app, configure recurring jobs:
#
# For Solid Queue (config/recurring.yml):
#
# parser:
#   class: SolidLog::ParserJob
#   schedule: every 10 seconds
#   args: []
#
# cache_cleanup:
#   class: SolidLog::CacheCleanupJob
#   schedule: every hour
#   args: []
#
# retention:
#   class: SolidLog::RetentionJob
#   schedule: every day at 2am
#   args: [{ retention_days: 30, error_retention_days: 90 }]
#
# field_analysis:
#   class: SolidLog::FieldAnalysisJob
#   schedule: every day at 3am
#   args: [{ auto_promote: false }]

# Or programmatically with Solid Queue:
# if defined?(SolidQueue)
#   SolidQueue::RecurringTask.find_or_create_by!(key: 'solidlog_parser') do |task|
#     task.class_name = 'SolidLog::ParserJob'
#     task.schedule = 'every 10 seconds'
#   end
#
#   SolidQueue::RecurringTask.find_or_create_by!(key: 'solidlog_cache_cleanup') do |task|
#     task.class_name = 'SolidLog::CacheCleanupJob'
#     task.schedule = 'every hour'
#   end
#
#   # ... etc
# end
