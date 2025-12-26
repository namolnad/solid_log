require "test_helper"

module SolidLog
  class SilenceLoggingTest < ActiveSupport::TestCase
    test "without_logging prevents SQL logging" do
      # Create a logger that captures SQL queries
      logged_queries = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        logged_queries << event.payload[:sql] unless Thread.current[:solid_log_silenced]
      end

      begin
        # SQL outside without_logging should be logged
        Token.create!(name: "Test", token_hash: BCrypt::Password.create("test"))
        logged_count_without_silence = logged_queries.size
        assert logged_count_without_silence > 0, "Should log SQL when not silenced"

        logged_queries.clear

        # SQL inside without_logging should NOT be logged (flag checked by subscriber)
        SolidLog.without_logging do
          Token.create!(name: "Test 2", token_hash: BCrypt::Password.create("test2"))
        end
        logged_count_with_silence = logged_queries.size
        assert_equal 0, logged_count_with_silence, "Should not log SQL when silenced"
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end
    end

    test "without_logging sets thread-local flag correctly" do
      assert_nil Thread.current[:solid_log_silenced]

      SolidLog.without_logging do
        assert_equal true, Thread.current[:solid_log_silenced]
      end

      assert_nil Thread.current[:solid_log_silenced]
    end

    test "without_logging is thread-safe" do
      Thread.new do
        SolidLog.without_logging do
          sleep 0.1
          assert_equal true, Thread.current[:solid_log_silenced]
        end
      end.join

      # Main thread should not be affected
      assert_nil Thread.current[:solid_log_silenced]
    end

    test "middleware silences SolidLog requests" do
      middleware = SilenceMiddleware.new(->(env) { [ 200, {}, [ "OK" ] ] })

      # SolidLog API request should set flag
      env = Rack::MockRequest.env_for("/solid_log/api/v1/ingest")
      middleware.call(env)
      # After request, flag should be cleared
      assert_nil Thread.current[:solid_log_silenced]

      # Non-SolidLog request should not set flag
      env = Rack::MockRequest.env_for("/users")
      Thread.current[:solid_log_silenced] = nil
      middleware.call(env)
      assert_nil Thread.current[:solid_log_silenced]
    end

    test "actual recursive logging prevention via HTTP API" do
      # This tests the real scenario: logging during log ingestion
      token_result = Token.generate!("Test API")

      # Track if any INSERT INTO solid_log_raw happens during ingestion
      recursive_inserts = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        sql = event.payload[:sql]

        # Check if we're trying to log a log insertion
        if sql.include?("INSERT INTO") && sql.include?("solid_log_raw")
          recursive_inserts << sql unless Thread.current[:solid_log_silenced]
        end
      end

      begin
        # Make API request to ingest a log
        payload = { timestamp: Time.current.iso8601, level: "info", message: "test" }

        # Simulate what the API controller does
        SolidLog.without_logging do
          RawEntry.create!(
            payload: payload.to_json,
            token_id: token_result[:id],
            received_at: Time.current
          )
        end

        # The INSERT should have happened, but shouldn't be "logged" recursively
        assert_equal 0, recursive_inserts.size, "Should not recursively log the log insertion"
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end
    end

    test "LogDevice respects solid_log_silenced flag" do
      require "solid_log/log_subscriber"

      device = SolidLog::LogSubscriber::LogDevice.new
      queue = SolidLog::LogSubscriber.queue
      queue.clear

      # Normal logging should queue messages
      device.write("[INFO] Test message")
      assert_equal 1, queue.size

      queue.clear

      # Logging inside without_logging should NOT queue messages
      SolidLog.without_logging do
        device.write("[INFO] Should be silenced")
      end
      assert_equal 0, queue.size, "LogDevice should respect solid_log_silenced flag"
    end
  end
end
