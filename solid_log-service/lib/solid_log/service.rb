require 'solid_log/core'
require_relative 'service/version'
require_relative 'service/configuration'
require_relative 'service/scheduler'
require_relative 'service/job_processor'
require_relative 'service/engine'

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

      # Start the service (job processor)
      def start!
        JobProcessor.setup
      end

      # Stop the service
      def stop!
        JobProcessor.stop
      end
    end
  end
end
