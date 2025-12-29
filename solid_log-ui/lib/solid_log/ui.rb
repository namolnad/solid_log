require "solid_log/core"
require_relative "ui/version"
require_relative "ui/configuration"
require_relative "ui/data_source"
require_relative "ui/api_client"
require_relative "ui/engine" if defined?(Rails)

module SolidLog
  module UI
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
    end
  end
end
