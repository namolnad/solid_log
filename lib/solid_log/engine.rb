require_relative 'silence_middleware'

module SolidLog
  class Engine < ::Rails::Engine
    isolate_namespace SolidLog

    # Configure assets to work with both Sprockets and Propshaft
    initializer "solid_log.assets" do |app|
      # Only configure if assets exists (Sprockets). Propshaft doesn't need this.
      if app.config.respond_to?(:assets)
        # Add asset paths
        app.config.assets.paths << root.join("app/assets/stylesheets")
        app.config.assets.paths << root.join("app/assets/javascripts")
        app.config.assets.paths << root.join("app/assets/images")

        # For Sprockets, explicitly add files to precompile list
        app.config.assets.precompile += %w[
          solid_log/application.css
          solid_log/components.css
          solid_log/stream_scroll.js
          solid_log/live_tail.js
          solid_log/checkbox_dropdown.js
          solid_log/timeline_histogram.js
          solid_log/log_filters.js
          solid_log/filter_state.js
        ]
      end
      # Propshaft automatically discovers assets in app/assets via its railtie
    end

    # Add middleware to silence SolidLog admin requests
    initializer "solid_log.add_middleware" do |app|
      app.middleware.use SolidLog::SilenceMiddleware
    end
  end
end
