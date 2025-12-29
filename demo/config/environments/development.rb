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

  # Highlight code that triggered database queries in logs
  config.active_record.verbose_query_logs = true

  # Highlight code that enqueued background job in logs
  config.active_job.verbose_enqueue_logs = true

  # Suppress logger output for asset requests
  config.assets.quiet = true if config.respond_to?(:assets)

  # Raise error when a before_action's only/except options reference missing actions
  config.action_controller.raise_on_missing_callback_actions = true
end
