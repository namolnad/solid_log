require "solid_log/core"

module SolidLog
  module Service
    class Configuration < SolidLog::Core::Configuration
      attr_accessor :job_mode,
                    :parser_interval,
                    :cache_cleanup_interval,
                    :retention_hour,
                    :field_analysis_hour,
                    :websocket_enabled,
                    :cors_origins,
                    :bind,
                    :port

      def initialize
        super

        # Load from ENV vars with defaults
        # Job processing mode: :scheduler (default), :active_job, or :manual
        @job_mode = env_to_symbol("SOLIDLOG_JOB_MODE", :scheduler)

        # Scheduler intervals (only used when job_mode = :scheduler)
        @parser_interval = env_to_int("SOLIDLOG_PARSER_INTERVAL", 10)  # seconds
        @cache_cleanup_interval = env_to_int("SOLIDLOG_CACHE_CLEANUP_INTERVAL", 3600)  # seconds (1 hour)
        @retention_hour = env_to_int("SOLIDLOG_RETENTION_HOUR", 2)  # Hour of day (0-23)
        @field_analysis_hour = env_to_int("SOLIDLOG_FIELD_ANALYSIS_HOUR", 3)  # Hour of day (0-23)

        # WebSocket support for live tail
        @websocket_enabled = env_to_bool("SOLIDLOG_WEBSOCKET_ENABLED", false)

        # CORS configuration for API
        @cors_origins = env_to_array("SOLIDLOG_CORS_ORIGINS", [])

        # Server configuration
        @bind = ENV["SOLIDLOG_BIND"] || ENV["BIND"] || "0.0.0.0"
        @port = env_to_int("SOLIDLOG_PORT") || env_to_int("PORT", 3001)
      end

      # Validate configuration
      def valid?
        errors = []

        errors << "job_mode must be :scheduler, :active_job, or :manual" unless [:scheduler, :active_job, :manual].include?(job_mode)
        errors << "parser_interval must be positive" unless parser_interval&.positive?
        errors << "cache_cleanup_interval must be positive" unless cache_cleanup_interval&.positive?
        errors << "retention_hour must be between 0 and 23" unless retention_hour&.between?(0, 23)
        errors << "field_analysis_hour must be between 0 and 23" unless field_analysis_hour&.between?(0, 23)

        if errors.any?
          raise ArgumentError, "Invalid configuration:\n  #{errors.join("\n  ")}"
        end

        true
      end

      private

      def env_to_int(key, default = nil)
        value = ENV[key]
        return default if value.nil? || value.empty?
        value.to_i
      end

      def env_to_bool(key, default = false)
        value = ENV[key]
        return default if value.nil? || value.empty?
        ["true", "1", "yes", "on"].include?(value.downcase)
      end

      def env_to_symbol(key, default = nil)
        value = ENV[key]
        return default if value.nil? || value.empty?
        value.to_sym
      end

      def env_to_array(key, default = [])
        value = ENV[key]
        return default if value.nil? || value.empty?
        value.split(",").map(&:strip)
      end
    end
  end
end
