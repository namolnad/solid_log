require "solid_log/core"
require_relative "service/version"
require_relative "service/configuration"
require_relative "service/jobs/parser_job"
require_relative "service/jobs/cache_cleanup_job"
require_relative "service/jobs/retention_job"
require_relative "service/jobs/field_analysis_job"
require_relative "service/scheduler"
require_relative "service/job_processor"
require_relative "service/rack_app"

module SolidLog
  module Service
    class << self
      attr_writer :configuration

      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield(configuration)
        configuration.valid?
      end

      def reset_configuration!
        @configuration = Configuration.new
      end

      # Logger - delegates to SolidLog.logger (from core)
      def logger
        SolidLog.logger
      end

      def logger=(logger)
        SolidLog.logger = logger
      end

      # Start the service (job processor)
      def start!
        # Configure core logger if not already set
        unless SolidLog.logger
          require "logger"
          SolidLog.logger = Logger.new(STDOUT).tap do |log|
            log.level = ENV.fetch("LOG_LEVEL", "info").to_sym
          end
        end

        JobProcessor.setup
      end

      # Stop the service
      def stop!
        JobProcessor.stop
      end
    end
  end
end
