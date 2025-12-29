require "rails/engine"

module SolidLog
  module Service
    class Engine < ::Rails::Engine
      isolate_namespace SolidLog

      config.generators do |g|
        g.test_framework :minitest
        g.fixture_replacement :factory_bot
      end

      # Ensure controllers and jobs are autoloaded
      config.autoload_paths << root.join("app/controllers")
      config.autoload_paths << root.join("app/jobs")

      # Add SilenceMiddleware to prevent recursive logging
      # This intercepts all requests to the service and sets Thread.current[:solid_log_silenced]
      # so the service doesn't log its own API requests, parser jobs, etc.
      initializer "solid_log_service.add_middleware" do |app|
        app.middleware.use SolidLog::SilenceMiddleware
      end
    end
  end
end
