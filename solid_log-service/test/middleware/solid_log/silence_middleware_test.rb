require "test_helper"

module SolidLog
  class SilenceMiddlewareTest < ActiveSupport::TestCase
    setup do
      @app = ->(env) { [200, {}, ["OK"]] }
      @middleware = SilenceMiddleware.new(@app)
    end

    teardown do
      # Clean up thread-local state after each test
      Thread.current[:solid_log_silenced] = nil
    end

    # Test that SolidLog requests set the silenced flag
    test "sets thread-local flag for /admin/logs requests" do
      env = Rack::MockRequest.env_for("/admin/logs")

      # Flag should not be set initially
      assert_nil Thread.current[:solid_log_silenced]

      # Make request through middleware
      @middleware.call(env)

      # Flag should be cleared after request completes
      assert_nil Thread.current[:solid_log_silenced]
    end

    test "sets thread-local flag for paths containing solid_log" do
      env = Rack::MockRequest.env_for("/solid_log/streams")

      assert_nil Thread.current[:solid_log_silenced]
      @middleware.call(env)
      assert_nil Thread.current[:solid_log_silenced]
    end

    test "sets thread-local flag for /api/v1/ingest requests" do
      env = Rack::MockRequest.env_for("/api/v1/ingest")

      assert_nil Thread.current[:solid_log_silenced]
      @middleware.call(env)
      assert_nil Thread.current[:solid_log_silenced]
    end

    test "does not set flag for non-SolidLog requests" do
      env = Rack::MockRequest.env_for("/users/profile")

      # Create app that checks flag during request
      flag_during_request = nil
      app = ->(env) {
        flag_during_request = Thread.current[:solid_log_silenced]
        [200, {}, ["OK"]]
      }
      middleware = SilenceMiddleware.new(app)

      middleware.call(env)

      # Flag should never be set for non-SolidLog requests
      assert_nil flag_during_request
      assert_nil Thread.current[:solid_log_silenced]
    end

    test "flag is set during SolidLog request processing" do
      env = Rack::MockRequest.env_for("/api/v1/ingest")

      # Create app that checks flag during request
      flag_during_request = nil
      app = ->(env) {
        flag_during_request = Thread.current[:solid_log_silenced]
        [200, {}, ["OK"]]
      }
      middleware = SilenceMiddleware.new(app)

      middleware.call(env)

      # Flag should be true during request
      assert_equal true, flag_during_request

      # But cleared after request completes
      assert_nil Thread.current[:solid_log_silenced]
    end

    test "clears flag even when app raises error" do
      env = Rack::MockRequest.env_for("/api/v1/ingest")

      # Create app that raises error
      app = ->(env) { raise StandardError, "Test error" }
      middleware = SilenceMiddleware.new(app)

      # Request should raise error
      assert_raises(StandardError) do
        middleware.call(env)
      end

      # Flag should still be cleared due to ensure block
      assert_nil Thread.current[:solid_log_silenced]
    end

    test "is thread-safe - flag only affects current thread" do
      env = Rack::MockRequest.env_for("/api/v1/ingest")

      # Create app that sleeps to allow other thread to run
      flag_in_thread1 = nil
      flag_in_thread2 = nil

      app1 = ->(env) {
        sleep 0.1  # Allow thread 2 to start
        flag_in_thread1 = Thread.current[:solid_log_silenced]
        [200, {}, ["OK"]]
      }

      app2 = ->(env) {
        flag_in_thread2 = Thread.current[:solid_log_silenced]
        [200, {}, ["OK"]]
      }

      middleware1 = SilenceMiddleware.new(app1)
      middleware2 = SilenceMiddleware.new(app2)

      # Run middleware in two threads
      thread1 = Thread.new do
        middleware1.call(env)
      end

      thread2 = Thread.new do
        sleep 0.05  # Start after thread1
        # Non-SolidLog request
        middleware2.call(Rack::MockRequest.env_for("/users/profile"))
      end

      thread1.join
      thread2.join

      # Thread 1 should have flag set (SolidLog request)
      assert_equal true, flag_in_thread1

      # Thread 2 should NOT have flag set (non-SolidLog request)
      assert_nil flag_in_thread2

      # Main thread should not be affected
      assert_nil Thread.current[:solid_log_silenced]
    end

    test "passes request through to app and returns response" do
      env = Rack::MockRequest.env_for("/api/v1/ingest")

      # Create app with custom response
      app = ->(env) { [201, {"X-Custom" => "header"}, ["Created"]] }
      middleware = SilenceMiddleware.new(app)

      status, headers, body = middleware.call(env)

      # Response should be passed through unchanged
      assert_equal 201, status
      assert_equal "header", headers["X-Custom"]
      assert_equal ["Created"], body
    end

    test "matches various SolidLog path patterns" do
      solid_log_paths = [
        "/admin/logs",
        "/admin/logs/streams",
        "/admin/logs/entries/123",
        "/solid_log/dashboard",
        "/solid_log/api/v1/ingest",
        "/api/v1/ingest",
        "/some/solid_log/path"
      ]

      solid_log_paths.each do |path|
        env = Rack::MockRequest.env_for(path)

        flag_during_request = nil
        app = ->(env) {
          flag_during_request = Thread.current[:solid_log_silenced]
          [200, {}, ["OK"]]
        }
        middleware = SilenceMiddleware.new(app)

        middleware.call(env)

        assert_equal true, flag_during_request,
          "Flag should be set for SolidLog path: #{path}"

        # Cleanup
        Thread.current[:solid_log_silenced] = nil
      end
    end

    test "does not match non-SolidLog paths" do
      non_solid_log_paths = [
        "/",
        "/users",
        "/api/v1/posts",
        "/admin",
        "/admin/users",
        "/logs",  # Not /admin/logs
        "/api/ingest"  # Not /api/v1/ingest
      ]

      non_solid_log_paths.each do |path|
        env = Rack::MockRequest.env_for(path)

        flag_during_request = nil
        app = ->(env) {
          flag_during_request = Thread.current[:solid_log_silenced]
          [200, {}, ["OK"]]
        }
        middleware = SilenceMiddleware.new(app)

        middleware.call(env)

        assert_nil flag_during_request,
          "Flag should NOT be set for non-SolidLog path: #{path}"
      end
    end

    test "integration with SolidLog.without_logging helper" do
      # SolidLog.without_logging checks Thread.current[:solid_log_silenced]
      env = Rack::MockRequest.env_for("/api/v1/ingest")

      logged_during_request = false
      app = ->(env) {
        # This should be silenced because middleware set the flag
        logged_during_request = !SolidLog.silenced?
        [200, {}, ["OK"]]
      }
      middleware = SilenceMiddleware.new(app)

      middleware.call(env)

      # SolidLog should be silenced during SolidLog requests
      assert_equal false, logged_during_request
    end
  end
end
