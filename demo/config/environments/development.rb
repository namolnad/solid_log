require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # In development, eager loading is disabled by default for faster start times
  config.enable_reloading = true
  config.eager_load = false

  # Show full error reports
  config.consider_all_requests_local = true

  # Enable caching (required for live tail filter registration)
  config.action_controller.perform_caching = true
  config.cache_store = :memory_store

  # Print deprecation notices
  config.active_support.deprecation = :log

  # Raise exceptions for disallowed deprecations
  config.active_support.disallowed_deprecation = :raise
  config.active_support.disallowed_deprecation_warnings = []

  # Raise an error on page load if there are pending migrations
  config.active_record.migration_error = :page_load

  # Disable verbose query logs to reduce noise (SolidLog logs everything anyway)
  config.active_record.verbose_query_logs = false

  # Highlight code that enqueued background job in logs
  config.active_job.verbose_enqueue_logs = true

  # Suppress logger output for asset requests
  config.assets.quiet = true if config.respond_to?(:assets)

  # Raise error when a before_action's only/except options reference missing actions
  config.action_controller.raise_on_missing_callback_actions = true

  # Configure Rails.logger to use SolidLog DirectLogger
  # This makes ALL Rails logging go to SolidLog (no HTTP, no tokens needed)
  config.logger = ActiveSupport::Logger.new(SolidLog::DirectLogger.new)

  # Configure lograge to use the same logger
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new
  config.lograge.logger = config.logger

  # Ignore SolidLog's own requests and ActionCable events to prevent recursion/errors
  config.lograge.ignore_custom = lambda do |event|
    # Ignore all SolidLog controller requests
    return true if event.payload[:controller]&.include?('SolidLog')

    # Ignore ActionCable events (they have different payload structure)
    return true if event.name&.include?('action_cable')

    false
  end

  # Include useful request data (only for HTTP requests)
  config.lograge.custom_options = lambda do |event|
    # Skip for ActionCable events
    return {} if event.name&.include?('action_cable')

    headers = event.payload[:headers] || {}
    {
      app: 'demo-app',
      env: Rails.env,
      host: event.payload[:host],
      remote_ip: event.payload[:remote_ip],
      user_agent: headers['HTTP_USER_AGENT'],
      request_id: headers['action_dispatch.request_id']
    }
  rescue => e
    # If custom_options fails, return empty hash to avoid breaking lograge
    {}
  end
end
