module SolidLog
  # DirectLogger writes logs directly to the database, bypassing HTTP overhead.
  # This is optimized for the parent Rails application that has direct database access.
  #
  # Features:
  # - Batches logs in memory for performance
  # - Flushes on size threshold (default: 100 logs)
  # - Flushes on time threshold (default: 5 seconds)
  # - Thread-safe
  # - Flushes remaining logs on process exit
  #
  # Usage:
  #   config.lograge.logger = ActiveSupport::Logger.new(SolidLog::DirectLogger.new)
  class DirectLogger
    attr_reader :buffer_size, :flush_interval, :last_flush_time

    def initialize(batch_size: nil, flush_interval: 5, token_id: nil, eager_flush_levels: [:error, :fatal])
      @buffer = []
      @mutex = Mutex.new
      @batch_size = batch_size || SolidLog.configuration&.max_batch_size || 100
      @flush_interval = flush_interval # seconds
      @last_flush_time = Time.current
      @closed = false
      @eager_flush_levels = Array(eager_flush_levels).map(&:to_s)

      # Token ID priority: explicit param > ENV var > nil (for DirectLogger)
      # token_id is only needed for audit trail (tracking which source ingested the log)
      # For DirectLogger, nil is fine since we're logging internally
      @token_id = token_id || token_id_from_env

      # Start background flusher thread
      start_flush_thread

      # Ensure we flush on exit
      at_exit { close }
    end

    # Write a log message (called by Rails logger)
    # This is non-blocking - logs are buffered and flushed asynchronously
    # EXCEPT for error/fatal logs which flush immediately to prevent data loss on crash
    def write(message)
      return if @closed

      log_entry = parse_message(message)
      return unless log_entry # Skip if parsing failed

      # Check if this is a critical log that should flush immediately
      should_eager_flush = false
      if @eager_flush_levels.any?
        parsed_data = JSON.parse(log_entry[:payload]) rescue {}
        log_level = parsed_data["level"]&.to_s&.downcase
        should_eager_flush = @eager_flush_levels.include?(log_level)
      end

      @mutex.synchronize do
        @buffer << log_entry

        # Flush immediately if:
        # 1. Batch size reached, OR
        # 2. This is a critical log (error/fatal) to prevent loss on crash
        flush_internal if @buffer.size >= @batch_size || should_eager_flush
      end
    end

    # Explicitly flush all buffered logs
    # Useful for testing or before shutdown
    def flush
      @mutex.synchronize { flush_internal }
    end

    # Close the logger and flush remaining logs
    def close
      return if @closed
      @closed = true

      # Stop the flush thread
      @flush_thread&.kill

      # Flush remaining logs
      flush
    end

    # Get current buffer size (for monitoring/debugging)
    def buffer_size
      @mutex.synchronize { @buffer.size }
    end

    private

    # Parse a log message into the format expected by RawEntry
    def parse_message(message)
      # Handle different message formats
      if message.is_a?(String)
        # Try to parse as JSON (from Lograge)
        begin
          log_data = JSON.parse(message)
        rescue JSON::ParserError
          # Plain text log - wrap in JSON
          log_data = {
            message: message.strip,
            timestamp: Time.current.utc.iso8601,
            level: "info"
          }
        end
      elsif message.is_a?(Hash)
        log_data = message
      else
        # Unsupported format
        return nil
      end

      # Return in RawEntry format
      {
        payload: log_data.to_json,
        token_id: @token_id,
        received_at: Time.current
      }
    rescue => e
      # If parsing fails, log to stderr but don't crash
      $stderr.puts "SolidLog::DirectLogger parse error: #{e.message}"
      nil
    end

    # Internal flush (must be called within mutex.synchronize)
    def flush_internal
      return if @buffer.empty?

      batch = @buffer.dup
      @buffer.clear
      @last_flush_time = Time.current

      # Release mutex before database write
      @mutex.unlock

      begin
        # Write batch to database
        write_batch(batch)
      ensure
        # Re-acquire mutex
        @mutex.lock
      end
    rescue => e
      # On error, log to stderr
      $stderr.puts "SolidLog::DirectLogger flush error: #{e.message}"
      $stderr.puts e.backtrace.first(5).join("\n")
    end

    # Write a batch of logs to the database
    def write_batch(batch)
      return if batch.empty?

      # Prevent recursive logging
      SolidLog.without_logging do
        # Ensure we have an ActiveRecord connection in this thread
        ActiveRecord::Base.connection_pool.with_connection do
          # Use insert_all for performance (single SQL statement)
          RawEntry.insert_all(batch)
        end
      end
    end

    # Try to get token_id from environment variable
    # This is useful for audit trail (tracking which source ingested logs)
    def token_id_from_env
      # Check for SOLIDLOG_TOKEN_ID env var
      token_id = ENV["SOLIDLOG_TOKEN_ID"]
      return nil unless token_id

      # Validate it's a number
      token_id.to_i if token_id.match?(/^\d+$/)
    end

    # Start background thread that flushes periodically
    def start_flush_thread
      @flush_thread = Thread.new do
        loop do
          sleep @flush_interval

          # Check if we need to flush based on time
          @mutex.synchronize do
            time_since_flush = Time.current - @last_flush_time
            flush_internal if time_since_flush >= @flush_interval && @buffer.any?
          end
        end
      rescue => e
        # Thread died - log but don't crash
        $stderr.puts "SolidLog::DirectLogger flush thread error: #{e.message}"
      end

      # Make it a daemon thread so it doesn't prevent process exit
      @flush_thread.abort_on_exception = false

      # Set thread priority lower so it doesn't interfere with app
      @flush_thread.priority = -1
    end
  end
end
