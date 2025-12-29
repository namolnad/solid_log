require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile
Bundler.require(*Rails.groups)

module SolidLogTestApp
  class Application < Rails::Application
    config.load_defaults 8.0

    # For compatibility with applications that use this config
    config.action_controller.include_all_helpers = false

    # Autoload lib directory
    config.autoload_lib(ignore: %w[assets tasks])

    # Set up multi-database for SolidLog
    config.active_record.database_selector = nil
    config.active_record.database_resolver = nil
    config.active_record.database_resolver_context = nil

    # Time zone
    config.time_zone = "UTC"

    # Eager load paths - ensure we load SolidLog models
    config.eager_load_paths << Rails.root.join("app", "models", "solid_log").to_s
  end
end
