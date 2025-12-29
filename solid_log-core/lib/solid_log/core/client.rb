require_relative 'client/configuration'
require_relative 'client/buffer'
require_relative 'client/http'
require_relative 'client/retry_handler'
require_relative 'client/lograge_formatter'

module SolidLog
  module Core
    class Client
      class << self
        attr_writer :configuration

        def configuration
          @configuration ||= ClientConfiguration.new
        end

        def configure
          yield(configuration)
          initialize_client
        end

        # Get logger instance for Lograge integration
        def logger
          @logger ||= BufferedLogger.new
        end

        # Log a single entry
        def log(entry)
          return unless configuration.enabled

          buffer.add(entry)
        end

        # Flush pending logs immediately
        def flush
          buffer.flush
        end

        # Start background flushing (if not already started)
        def start
          buffer.start_auto_flush
        end

        # Stop background flushing and flush pending logs
        def stop
          buffer.stop_auto_flush
          flush
        end

        private

        def buffer
          @buffer ||= Buffer.new(
            http_sender: http_sender,
            batch_size: configuration.batch_size,
            flush_interval: configuration.flush_interval,
            max_queue_size: configuration.max_queue_size
          )
        end

        def http_sender
          @http_sender ||= HttpSender.new(
            url: configuration.service_url,
            token: configuration.token,
            retry_handler: retry_handler
          )
        end

        def retry_handler
          @retry_handler ||= RetryHandler.new(
            max_attempts: configuration.retry_max_attempts
          )
        end

        def initialize_client
          # Reset instances when configuration changes
          @buffer = nil
          @http_sender = nil
          @retry_handler = nil
          @logger = nil
        end
      end

      # BufferedLogger for Lograge integration
      class BufferedLogger
        def initialize
          @client = Client
        end

        def info(message)
          log_message(message, level: "info")
        end

        def debug(message)
          log_message(message, level: "debug")
        end

        def warn(message)
          log_message(message, level: "warn")
        end

        def error(message)
          log_message(message, level: "error")
        end

        def fatal(message)
          log_message(message, level: "fatal")
        end

        def <<(message)
          log_message(message, level: "info")
        end

        private

        def log_message(message, level:)
          # Parse JSON if message is a string
          entry = if message.is_a?(String)
                   begin
                     JSON.parse(message).merge(level: level)
                   rescue JSON::ParserError
                     { message: message, level: level }
                   end
                 else
                   message.merge(level: level)
                 end

          # Add default fields
          entry[:timestamp] ||= Time.current.iso8601
          entry[:app] ||= Client.configuration.app_name
          entry[:env] ||= Client.configuration.environment

          @client.log(entry)
        end
      end
    end
  end
end
