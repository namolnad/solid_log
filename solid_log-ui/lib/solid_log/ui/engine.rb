require "importmap-rails"
require "turbo-rails"
require "stimulus-rails"

module SolidLog
  module UI
    class Engine < ::Rails::Engine
      isolate_namespace SolidLog::UI

      config.generators do |g|
        g.test_framework :test_unit
        g.assets false
        g.helper false
      end

      # Configure assets (works with both Sprockets and Propshaft)
      initializer "solid_log_ui.assets" do |app|
        # Add asset paths for both Sprockets and Propshaft
        if app.config.respond_to?(:assets)
          # Sprockets
          app.config.assets.paths << root.join("app/assets/stylesheets")
          app.config.assets.paths << root.join("app/assets/javascripts")
          app.config.assets.paths << root.join("app/assets/images")

          app.config.assets.precompile += %w[
            solid_log/**/*.css
            solid_log/**/*.js
          ]
        end

        # Propshaft
        if Rails.application.config.respond_to?(:assets) && Rails.application.config.assets.respond_to?(:paths)
          Rails.application.config.assets.paths << root.join("app/assets/stylesheets")
          Rails.application.config.assets.paths << root.join("app/assets/javascripts")
          Rails.application.config.assets.paths << root.join("app/assets/images")
        end
      end

      # Configure importmap for the engine
      initializer "solid_log_ui.importmap", before: "importmap" do |app|
        app.config.importmap.paths << root.join("config/importmap.rb")
        app.config.importmap.cache_sweepers << root.join("app/assets/javascripts")
      end

      # Set up inflections for UI acronym
      initializer "solid_log_ui.inflections" do
        ActiveSupport::Inflector.inflections(:en) do |inflect|
          inflect.acronym "UI"
        end
      end

      # Load configuration if it exists
      initializer "solid_log_ui.load_config" do
        config_file = Rails.root.join("config/initializers/solid_log_ui.rb")
        load config_file if File.exist?(config_file)
      end

      # Add SilenceMiddleware to main app's middleware stack
      # This prevents the UI from logging its own queries/requests
      initializer "solid_log_ui.add_middleware" do |app|
        app.middleware.use SolidLog::SilenceMiddleware
      end

      # Register Action Cable channels
      initializer "solid_log_ui.action_cable" do
        engine_root = root
        config.to_prepare do
          # Ensure channel classes are loaded and available to ActionCable
          Dir[engine_root.join("app/channels/**/*_channel.rb")].each do |file|
            require_dependency file
          end
        end
      end
    end
  end
end
