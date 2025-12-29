require 'thread'

module SolidLog
  module Core
    class Buffer
      attr_reader :queue, :mutex, :flush_thread

      def initialize(http_sender:, batch_size: 100, flush_interval: 5, max_queue_size: 10_000)
        @http_sender = http_sender
        @batch_size = batch_size
        @flush_interval = flush_interval
        @max_queue_size = max_queue_size

        @queue = []
        @mutex = Mutex.new
        @flush_thread = nil
        @running = false
      end

      # Add entry to buffer
      def add(entry)
        @mutex.synchronize do
          # Drop oldest entries if queue is full
          @queue.shift if @queue.size >= @max_queue_size

          @queue << normalize_entry(entry)

          # Auto-flush if batch size reached
          flush_if_needed
        end
      end

      # Flush pending entries
      def flush
        entries_to_send = []

        @mutex.synchronize do
          return if @queue.empty?

          # Take up to batch_size entries
          entries_to_send = @queue.shift(@batch_size)
        end

        # Send outside of mutex lock
        send_entries(entries_to_send) if entries_to_send.any?
      end

      # Start automatic flushing in background thread
      def start_auto_flush
        return if @running

        @running = true
        @flush_thread = Thread.new do
          loop do
            sleep @flush_interval
            break unless @running

            begin
              flush
            rescue => e
              Rails.logger.error "SolidLog::Client: Auto-flush error: #{e.message}" if defined?(Rails)
            end
          end
        end
      end

      # Stop automatic flushing
      def stop_auto_flush
        @running = false
        @flush_thread&.join
        @flush_thread = nil
      end

      # Get current queue size
      def size
        @mutex.synchronize { @queue.size }
      end

      private

      def flush_if_needed
        flush if @queue.size >= @batch_size
      end

      def send_entries(entries)
        @http_sender.send_batch(entries)
      rescue => e
        Rails.logger.error "SolidLog::Client: Failed to send batch: #{e.message}" if defined?(Rails)

        # Put entries back in queue for retry
        @mutex.synchronize do
          @queue.unshift(*entries)

          # Trim queue if it exceeds max size
          while @queue.size > @max_queue_size
            @queue.shift
          end
        end
      end

      def normalize_entry(entry)
        # Ensure entry is a hash
        entry = entry.to_h if entry.respond_to?(:to_h)

        # Add timestamp if missing
        entry[:timestamp] ||= Time.current.iso8601

        entry
      end
    end
  end
end
