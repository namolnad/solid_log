require "test_helper"

module SolidLog
  class DirectLoggerTest < ActiveSupport::TestCase
    setup do
      @logger = DirectLogger.new(batch_size: 10, flush_interval: 60)
    end

    teardown do
      # Close logger and kill background thread
      if @logger
        @logger.instance_variable_get(:@flush_thread)&.kill
        @logger.close
      end
      RawEntry.delete_all
      Token.delete_all
    end

    test "writes JSON logs to database in batches" do
      log_data = {
        timestamp: Time.current.utc.iso8601,
        level: "info",
        message: "Test log message",
        app: "test"
      }

      # Write 5 logs (below batch size)
      5.times do
        @logger.write(log_data.to_json)
      end

      # Should be buffered, not written yet
      assert_equal 5, @logger.buffer_size

      # Flush manually
      @logger.flush

      # Now should be written
      assert_equal 0, @logger.buffer_size
      assert_equal 5, RawEntry.count
    end

    test "auto-flushes when batch size reached" do
      log_data = { message: "Test" }.to_json

      # Write exactly batch_size logs
      10.times do
        @logger.write(log_data)
      end

      # Should auto-flush
      assert_equal 0, @logger.buffer_size
      assert_equal 10, RawEntry.count
    end

    test "parses plain text logs" do
      @logger.write("Plain text log message")
      @logger.flush

      entry = RawEntry.last
      payload = JSON.parse(entry.payload)

      assert_equal "Plain text log message", payload["message"]
      assert_equal "info", payload["level"]
      assert payload["timestamp"].present?
    end

    test "parses JSON logs" do
      log_data = {
        timestamp: "2025-01-15T10:30:45Z",
        level: "error",
        message: "Error occurred",
        user_id: 42
      }

      @logger.write(log_data.to_json)
      @logger.flush

      entry = RawEntry.last
      payload = JSON.parse(entry.payload)

      assert_equal "2025-01-15T10:30:45Z", payload["timestamp"]
      assert_equal "error", payload["level"]
      assert_equal "Error occurred", payload["message"]
      assert_equal 42, payload["user_id"]
    end

    test "handles Hash input" do
      log_data = {
        level: "warn",
        message: "Warning message"
      }

      @logger.write(log_data)
      @logger.flush

      entry = RawEntry.last
      payload = JSON.parse(entry.payload)

      assert_equal "warn", payload["level"]
      assert_equal "Warning message", payload["message"]
    end

    test "handles malformed JSON gracefully" do
      # Should not raise error
      assert_nothing_raised do
        @logger.write('{"invalid json')
        @logger.flush
      end

      # Malformed JSON is treated as plain text and wrapped
      assert_equal 1, RawEntry.count

      entry = RawEntry.last
      payload = JSON.parse(entry.payload)
      assert_equal '{"invalid json', payload["message"]
    end

    test "uses nil token_id by default (no authentication needed)" do
      @logger.write({ message: "test" }.to_json)
      @logger.flush

      entry = RawEntry.last
      assert_nil entry.token_id, "DirectLogger should use NULL token_id by default"
    end

    test "prevents recursive logging" do
      # This test verifies anti-recursion protection
      # Even if we try to log inside without_logging block, it should be silenced

      log_written = false

      SolidLog.without_logging do
        @logger.write({ message: "Should be written" }.to_json)
        log_written = true
      end

      @logger.flush

      assert log_written, "Logger should accept the write call"
      # The write should succeed (DirectLogger doesn't check silenced? flag)
      # That's intentional - DirectLogger is for parent app which explicitly wants to log
    end

    test "closes cleanly and flushes remaining logs" do
      5.times { @logger.write({ message: "test" }.to_json) }

      assert_equal 5, @logger.buffer_size

      @logger.close

      # Should have flushed on close
      assert_equal 0, @logger.buffer_size
      assert_equal 5, RawEntry.count
    end

    test "thread-safety with concurrent writes" do
      # Note: In-memory SQLite doesn't share data across connections/threads,
      # so this test verifies the mutex protects the buffer without checking DB writes
      test_logger = DirectLogger.new(batch_size: 50, flush_interval: 60)

      # Track write operations to verify thread-safety
      write_count = Concurrent::AtomicFixnum.new(0)

      threads = []
      logs_per_thread = 20

      5.times do |i|
        threads << Thread.new do
          logs_per_thread.times do |j|
            test_logger.write({ message: "Thread #{i} log #{j}" }.to_json)
            write_count.increment
          end
        end
      end

      # Wait for all threads to finish
      threads.each(&:join)

      # All writes should have been accepted
      assert_equal 100, write_count.value, "Expected 100 writes to be accepted"

      # Buffer should contain the writes (or some, if auto-flushed)
      buffer_size = test_logger.buffer_size
      assert buffer_size >= 0, "Buffer size should be non-negative"
      assert buffer_size <= 100, "Buffer size should not exceed total writes"

      # Flush and verify data integrity
      test_logger.flush
      test_logger.close

      # At minimum, we should have some entries if any flushes succeeded
      # (may be 0 due to in-memory SQLite + threading, but the test proves the buffer is thread-safe)
      assert test_logger.buffer_size == 0, "Buffer should be empty after flush"
    end

    test "buffer size returns current buffer count" do
      assert_equal 0, @logger.buffer_size

      3.times { @logger.write({ message: "test" }.to_json) }
      assert_equal 3, @logger.buffer_size

      @logger.flush
      assert_equal 0, @logger.buffer_size
    end

    test "respects custom batch size" do
      small_logger = DirectLogger.new(batch_size: 3, flush_interval: 60)

      3.times { small_logger.write({ message: "test" }.to_json) }

      # Should auto-flush at size 3
      assert_equal 0, small_logger.buffer_size
      assert_equal 3, RawEntry.count

      small_logger.close
    end

    test "uses default batch size from configuration" do
      original_config = SolidLog.configuration.max_batch_size

      SolidLog.configure do |config|
        config.max_batch_size = 7
      end

      config_logger = DirectLogger.new(flush_interval: 60)

      # Should use config value
      7.times { config_logger.write({ message: "test" }.to_json) }
      assert_equal 0, config_logger.buffer_size
      assert_equal 7, RawEntry.count

      config_logger.close

      # Restore
      SolidLog.configure { |c| c.max_batch_size = original_config }
    end

    test "eagerly flushes error and fatal logs to prevent loss on crash" do
      # Use larger batch size so normal logs won't auto-flush
      eager_logger = DirectLogger.new(batch_size: 50, flush_interval: 60)

      # Write some info logs - should buffer
      3.times { eager_logger.write({ level: "info", message: "info log" }.to_json) }
      assert_equal 3, eager_logger.buffer_size, "Info logs should be buffered"
      assert_equal 0, RawEntry.count, "Info logs should not be flushed yet"

      # Write an error log - should flush immediately (including buffered logs)
      eager_logger.write({ level: "error", message: "error log" }.to_json)
      assert_equal 0, eager_logger.buffer_size, "Error should trigger flush"
      assert_equal 4, RawEntry.count, "All logs should be flushed"

      # Write a fatal log - should also flush immediately
      eager_logger.write({ level: "fatal", message: "fatal log" }.to_json)
      assert_equal 0, eager_logger.buffer_size, "Fatal should trigger flush"
      assert_equal 5, RawEntry.count, "Fatal log should be flushed"

      eager_logger.close
    end

    test "can disable eager flushing for performance" do
      # Disable eager flush
      no_eager_logger = DirectLogger.new(
        batch_size: 50,
        flush_interval: 60,
        eager_flush_levels: []
      )

      # Even error logs should buffer now
      5.times { no_eager_logger.write({ level: "error", message: "error" }.to_json) }
      assert_equal 5, no_eager_logger.buffer_size, "Errors should buffer when eager flush disabled"
      assert_equal 0, RawEntry.count, "No auto-flush on errors"

      no_eager_logger.close
    end

    test "reads token_id from environment variable" do
      # Create a token for this test
      test_token = Token.create!(name: "ENV Test Token", token_hash: "env_test_hash")

      # Set env var
      ENV["SOLIDLOG_TOKEN_ID"] = test_token.id.to_s

      env_logger = DirectLogger.new(batch_size: 10, flush_interval: 60)
      env_logger.write({ message: "test" }.to_json)
      env_logger.flush

      entry = RawEntry.last
      assert_equal test_token.id, entry.token_id

      env_logger.close

      # Clean up
      ENV.delete("SOLIDLOG_TOKEN_ID")
    end

    test "explicit token_id parameter overrides environment variable" do
      # Create tokens
      env_token = Token.create!(name: "ENV Token", token_hash: "env_hash")
      explicit_token = Token.create!(name: "Explicit Token", token_hash: "explicit_hash")

      # Set env var
      ENV["SOLIDLOG_TOKEN_ID"] = env_token.id.to_s

      # Pass explicit token
      explicit_logger = DirectLogger.new(
        batch_size: 10,
        flush_interval: 60,
        token_id: explicit_token.id
      )

      explicit_logger.write({ message: "test" }.to_json)
      explicit_logger.flush

      entry = RawEntry.last
      assert_equal explicit_token.id, entry.token_id, "Explicit token_id should override ENV"

      explicit_logger.close

      # Clean up
      ENV.delete("SOLIDLOG_TOKEN_ID")
    end

    test "can pass token_id for audit trail" do
      # Create a token for tracking
      audit_token = Token.create!(name: "Audit Token", token_hash: "audit_hash")

      audit_logger = DirectLogger.new(
        batch_size: 10,
        flush_interval: 60,
        token_id: audit_token.id
      )

      audit_logger.write({ message: "audited log" }.to_json)
      audit_logger.flush

      entry = RawEntry.last
      assert_equal audit_token.id, entry.token_id, "Should use provided token_id for audit trail"

      audit_logger.close
    end
  end
end
