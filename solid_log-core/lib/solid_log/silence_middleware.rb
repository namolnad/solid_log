module SolidLog
  class SilenceMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      # Set thread-local flag BEFORE calling next middleware
      # This ensures it's set when the controller/logger runs
      Thread.current[:solid_log_silenced] = true if should_silence?(env)

      begin
        status, headers, body = @app.call(env)

        # Return response
        [status, headers, body]
      ensure
        Thread.current[:solid_log_silenced] = nil
      end
    end

    private

    def should_silence?(env)
      path = env["PATH_INFO"] || ""

      # Check path patterns for SolidLog UI and API routes
      # Match common mount points: /admin/logs, /solid_log, /solidlog, /logs/*
      # Also match API routes: /api/v1/ingest, /api/v1/logs
      path.start_with?("/admin/logs") ||
        path.include?("solid_log") ||
        path.include?("solidlog") ||
        path.start_with?("/api/v1/ingest") ||
        path.start_with?("/api/v1/logs") ||
        (path.start_with?("/logs/") && solid_log_ui_route?(path))
    end

    def solid_log_ui_route?(path)
      # Common SolidLog UI routes when mounted at /logs
      path.include?("/streams") ||
        path.include?("/entries") ||
        path.include?("/fields") ||
        path.include?("/search") ||
        path.include?("/export") ||
        path == "/logs" ||
        path == "/logs/"
    end
  end
end
