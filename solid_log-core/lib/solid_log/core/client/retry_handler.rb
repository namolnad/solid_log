module SolidLog
  module Core
    class RetryHandler
      def initialize(max_attempts: 3)
        @max_attempts = max_attempts
      end

      # Execute block with exponential backoff retry
      def with_retry(&block)
        attempts = 0

        begin
          attempts += 1
          yield
        rescue HttpSender::ServerError, HttpSender::UnexpectedError, StandardError => e
          if attempts < @max_attempts
            sleep_time = exponential_backoff(attempts)
            log_retry(attempts, sleep_time, e)
            sleep(sleep_time)
            retry
          else
            log_error "Max retry attempts (#{@max_attempts}) exceeded: #{e.message}"
            raise
          end
        rescue HttpSender::ClientError => e
          # Don't retry client errors (4xx)
          log_error "Client error, not retrying: #{e.message}"
          raise
        end
      end

      private

      def exponential_backoff(attempt)
        # 1s, 2s, 4s, 8s, etc.
        [2 ** (attempt - 1), 30].min # Cap at 30 seconds
      end

      def log_retry(attempt, sleep_time, error)
        Rails.logger.warn "SolidLog::Client: Retry attempt #{attempt}/#{@max_attempts} after #{sleep_time}s (#{error.class}: #{error.message})" if defined?(Rails)
      end

      def log_error(message)
        Rails.logger.error "SolidLog::Client: #{message}" if defined?(Rails)
      end
    end
  end
end
