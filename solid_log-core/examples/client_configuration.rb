# Example: Configure SolidLog::Core HTTP Client
# Place this in: config/initializers/solid_log_client.rb

# Configure the HTTP client to send logs to a remote SolidLog service
SolidLog::Core.configure_client do |config|
  # Service endpoint
  config.service_url = ENV['SOLIDLOG_SERVICE_URL'] || 'http://localhost:3001'

  # Authentication token (from solid_log service: rails solid_log:create_token)
  config.token = ENV['SOLIDLOG_TOKEN']

  # Application identifier
  config.app_name = 'web'

  # Environment
  config.environment = Rails.env

  # Batching settings
  config.batch_size = 100              # Send logs in batches of 100
  config.flush_interval = 5            # Flush every 5 seconds
  config.max_queue_size = 10_000       # Max logs to queue before dropping oldest

  # Retry settings
  config.retry_max_attempts = 3        # Retry failed sends up to 3 times

  # Enable/disable
  config.enabled = true                # Set to false to disable logging
end

# Start background flushing thread
SolidLog::Core::Client.start

# Ensure logs are flushed on shutdown
at_exit { SolidLog::Core::Client.stop }

# Optional: Integrate with Lograge
# config/environments/production.rb
if defined?(Lograge)
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new
  config.lograge.logger = SolidLog::Core::Client.logger
end

# Optional: Send custom logs
# SolidLog::Core::Client.log({
#   level: 'info',
#   message: 'User signed in',
#   user_id: 123,
#   ip: request.remote_ip
# })
