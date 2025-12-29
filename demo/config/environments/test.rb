require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  config.enable_reloading = false
  config.eager_load = ENV["CI"].present?

  # Configure public file server for tests with cache-control for performance
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  # Show full error reports
  config.consider_all_requests_local = true
  config.cache_store = :memory_store

  # Render exception templates for rescuable exceptions and raise for other exceptions
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment
  config.action_controller.allow_forgery_protection = false

  # Disable host authorization in test environment (required for integration tests)
  config.hosts.clear

  # Store uploaded files on the local file system in a temporary directory
  config.active_storage.service = :test if config.respond_to?(:active_storage)

  # Print deprecation notices to stderr
  config.active_support.deprecation = :stderr

  # Raise exceptions for disallowed deprecations
  config.active_support.disallowed_deprecation = :raise
  config.active_support.disallowed_deprecation_warnings = []

  # Raise error when a before_action's only/except options reference missing actions
  config.action_controller.raise_on_missing_callback_actions = true
end
