require 'rails'
require 'action_controller/railtie'
require 'active_record/railtie'
require 'active_job/railtie'
require 'action_cable/engine'

module SolidLog
  module Service
    class Application < Rails::Application
      config.load_defaults 8.0
      config.api_only = true

      # Enable caching with memory store
      config.cache_store = :memory_store

      # Load service configuration
      config.before_initialize do
        # Load configuration file if it exists
        config_file = Rails.root.join('config', 'solid_log_service.rb')
        require config_file if File.exist?(config_file)

        # Load Action Cable configuration
        cable_config_path = Rails.root.join('config', 'cable.yml')
        if File.exist?(cable_config_path)
          config.action_cable.cable = YAML.load_file(cable_config_path, aliases: true)[Rails.env]
        end
      end

      # Set up database connection
      config.before_initialize do
        db_config = {
          adapter: ENV['DB_ADAPTER'] || 'sqlite3',
          database: ENV['DATABASE_URL'] || Rails.root.join('storage', 'production_log.sqlite3').to_s,
          pool: ENV.fetch('RAILS_MAX_THREADS', 5)
        }

        ActiveRecord::Base.establish_connection(db_config)
      end

      # Start job processor after initialization (but not in console mode)
      config.after_initialize do
        unless defined?(Rails::Console)
          SolidLog::Service.start!
        end
      end

      # Stop job processor on shutdown
      at_exit do
        SolidLog::Service.stop!
      end

      # Eager load controllers and jobs
      config.eager_load_paths << Rails.root.join('app', 'controllers')
      config.eager_load_paths << Rails.root.join('app', 'jobs')

      # CORS configuration
      config.middleware.insert_before 0, Rack::Cors do
        allow do
          origins { |source, env| SolidLog::Service.configuration.cors_origins.include?(source) || SolidLog::Service.configuration.cors_origins.include?('*') }
          resource '*',
            headers: :any,
            methods: [:get, :post, :put, :patch, :delete, :options, :head],
            credentials: false
        end
      end if defined?(Rack::Cors)

      # Logging
      config.logger = ActiveSupport::Logger.new(STDOUT)
      config.log_level = ENV.fetch('LOG_LEVEL', 'info').to_sym
    end
  end
end
