module SolidLog
  # Optional ActiveSupport::LogSubscriber for sending Rails logs to SolidLog
  #
  # Usage in config/initializers/solid_log.rb:
  #   SolidLog::LogSubscriber.attach_to(:solid_log_client)
  #   Rails.logger.extend(ActiveSupport::TaggedLogging)
  #   Rails.logger.broadcast_to(SolidLog::LogSubscriber.logger)
  class LogSubscriber < ActiveSupport::LogSubscriber
    # Thread-safe queue for buffering logs
    @queue = Queue.new
    @flush_thread = nil
    @mutex = Mutex.new

    class << self
      attr_reader :queue

      def logger
        @logger ||= ActiveSupport::Logger.new(LogDevice.new)
      end

      # Start background thread to flush logs to SolidLog HTTP API
      def start_flush_thread(interval: 5, batch_size: 100)
        return if @flush_thread&.alive?

        @flush_thread = Thread.new do
          loop do
            sleep interval
            flush_batch(batch_size)
          rescue => e
            # Don't log errors from the log system itself
            warn "SolidLog::LogSubscriber flush error: #{e.message}"
          end
        end
      end

      def stop_flush_thread
        @flush_thread&.kill
        flush_batch(1000) # Final flush
      end

      def flush_batch(max_size)
        return if queue.empty?

        logs = []
        max_size.times do
          break if queue.empty?
          logs << queue.pop(true) rescue nil
        end

        return if logs.empty?

        send_to_solidlog(logs.compact)
      end

      private

      def send_to_solidlog(logs)
        # Don't recursively log SolidLog operations
        return if Thread.current[:solid_log_silenced]

        # Send logs via HTTP to SolidLog ingestion API
        # Users should configure token in initializer
        token = SolidLog.configuration.client_token
        return unless token

        uri = URI(SolidLog.configuration.ingestion_url || "http://localhost:3000/solid_log/api/v1/ingest")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = 5
        http.open_timeout = 5

        request = Net::HTTP::Post.new(uri.path)
        request["Authorization"] = "Bearer #{token}"
        request["Content-Type"] = "application/json"
        request.body = logs.to_json

        http.request(request)
      rescue => e
        # Silently fail - don't crash the app if logging fails
        warn "SolidLog::LogSubscriber send error: #{e.message}"
      end
    end

    # Custom LogDevice that queues logs instead of writing to IO
    class LogDevice
      def write(message)
        return if Thread.current[:solid_log_silenced]
        return if message.blank?

        # Parse log message and queue it
        # Expected format from Rails logger: "[LEVEL] message"
        if message =~ /\[(\w+)\]\s+(.+)/
          level = $1.downcase
          msg = $2.strip

          LogSubscriber.queue << {
            timestamp: Time.current.iso8601,
            level: level,
            message: msg,
            app: Rails.application.class.module_parent_name,
            env: Rails.env
          }
        else
          # Fallback for unparsed messages
          LogSubscriber.queue << {
            timestamp: Time.current.iso8601,
            level: "info",
            message: message.strip,
            app: Rails.application.class.module_parent_name,
            env: Rails.env
          }
        end
      end

      def close
        # No-op
      end
    end
  end
end
