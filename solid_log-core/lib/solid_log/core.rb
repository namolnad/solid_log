require "solid_log/core/version"
require "solid_log/core/configuration"
require "solid_log/core/client"
require "solid_log/silence_middleware"

# Database adapters
require "solid_log/adapters/base_adapter"
require "solid_log/adapters/sqlite_adapter"
require "solid_log/adapters/postgresql_adapter"
require "solid_log/adapters/mysql_adapter"
require "solid_log/adapters/adapter_factory"

# Parser
require "solid_log/parser"

# Loggers
require "solid_log/direct_logger"

# Service objects
require "solid_log/core/services/retention_service"
require "solid_log/core/services/field_analyzer"
require "solid_log/core/services/search_service"
require "solid_log/core/services/correlation_service"
require "solid_log/core/services/health_service"

# Models (explicit requires - no engine, no app/ directory)
require "solid_log/models/record"
require "solid_log/models/raw_entry"
require "solid_log/models/entry"
require "solid_log/models/token"
require "solid_log/models/field"
require "solid_log/models/facet_cache"

module SolidLog
  module Core
    class << self
      attr_writer :configuration

      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield(configuration)
      end

      def configure_client(&block)
        Client.configure(&block)
      end

      def reset_configuration!
        @configuration = Configuration.new
      end

      # Get database adapter
      def adapter
        SolidLog::Adapters::AdapterFactory.adapter
      end

      # Execute block without logging (prevent recursion)
      def without_logging
        Thread.current[:solid_log_silenced] = true
        yield
      ensure
        Thread.current[:solid_log_silenced] = nil
      end

      # Check if logging is silenced
      def silenced?
        Thread.current[:solid_log_silenced] == true
      end
    end
  end
end

# Legacy SolidLog module for backward compatibility with models
module SolidLog
  class << self
    def configuration
      Core.configuration
    end

    def configure(&block)
      Core.configure(&block)
    end

    def adapter
      Core.adapter
    end

    def without_logging(&block)
      Core.without_logging(&block)
    end

    def silenced?
      Core.silenced?
    end
  end

  # Alias service classes for easier access
  RetentionService = Core::RetentionService
  FieldAnalyzer = Core::FieldAnalyzer
  SearchService = Core::SearchService
  CorrelationService = Core::CorrelationService
  HealthService = Core::HealthService
end
