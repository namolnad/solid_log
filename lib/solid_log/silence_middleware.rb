module SolidLog
  class SilenceMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      request = Rack::Request.new(env)

      # Check if this is a SolidLog request (UI or API)
      if solid_log_request?(request)
        # Set thread-local flag to prevent SolidLog from logging its own requests
        Thread.current[:solid_log_silenced] = true

        begin
          @app.call(env)
        ensure
          Thread.current[:solid_log_silenced] = nil
        end
      else
        @app.call(env)
      end
    end

    private

    def solid_log_request?(request)
      # Match both UI routes (/admin/logs, /solid_log) and API routes (/api/v1/ingest)
      request.path.start_with?("/admin/logs") ||
        request.path.include?("solid_log") ||
        request.path.start_with?("/api/v1/ingest")
    end
  end
end
