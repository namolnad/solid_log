require "test_helper"

module SolidLog
  module UI
    class StreamsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @routes = Engine.routes
      end

      test "should get index" do
        get solid_log_ui.streams_path
        assert_response :success
      end

      test "should load entries" do
        get solid_log_ui.streams_path
        assert_response :success
        assert assigns(:entries).is_a?(ActiveRecord::Relation)
      end

      test "should load available filters" do
        get solid_log_ui.streams_path
        assert_response :success
        assert assigns(:available_filters).is_a?(Hash)
      end

      test "should filter by level" do
        # Create entries with different levels
        error_entry = create_entry(level: "error", message: "Error log")
        info_entry = create_entry(level: "info", message: "Info log")
        warn_entry = create_entry(level: "warn", message: "Warn log")

        get solid_log_ui.streams_path, params: { filters: { levels: ["error"] } }
        assert_response :success

        # Verify filter was applied
        assert_equal ["error"], assigns(:current_filters)[:levels]

        # Verify only error entries are returned
        entries = assigns(:entries).to_a
        assert_includes entries, error_entry
        assert_not_includes entries, info_entry
        assert_not_includes entries, warn_entry
        assert entries.all? { |e| e.level == "error" }
      end

      test "should filter by multiple levels" do
        # Create entries with different levels
        error_entry = create_entry(level: "error")
        fatal_entry = create_entry(level: "fatal")
        info_entry = create_entry(level: "info")

        get solid_log_ui.streams_path, params: { filters: { levels: ["error", "fatal"] } }

        entries = assigns(:entries).to_a
        assert_includes entries, error_entry
        assert_includes entries, fatal_entry
        assert_not_includes entries, info_entry
        assert entries.all? { |e| e.level.in?(%w[error fatal]) }
      end

      test "should filter by app" do
        # Create entries from different apps
        web_entry = create_entry(app: "web-app", message: "Web log")
        api_entry = create_entry(app: "api-app", message: "API log")

        get solid_log_ui.streams_path, params: { filters: { app: ["web-app"] } }
        assert_response :success

        # Verify filter was applied
        assert_equal ["web-app"], assigns(:current_filters)[:app]

        # Verify only web-app entries are returned
        entries = assigns(:entries).to_a
        assert_includes entries, web_entry
        assert_not_includes entries, api_entry
        assert entries.all? { |e| e.app == "web-app" }
      end

      test "should filter by environment" do
        # Create entries from different environments
        prod_entry = create_entry(env: "production")
        dev_entry = create_entry(env: "development")

        get solid_log_ui.streams_path, params: { filters: { env: ["production"] } }

        entries = assigns(:entries).to_a
        assert_includes entries, prod_entry
        assert_not_includes entries, dev_entry
        assert entries.all? { |e| e.env == "production" }
      end

      test "should handle pagination with before_id" do
        get solid_log_ui.streams_path, params: { before_id: 100 }, as: :turbo_stream
        assert_response :success
      end

      test "should handle pagination with after_id" do
        get solid_log_ui.streams_path, params: { after_id: 1 }, as: :turbo_stream
        assert_response :success
      end

      test "should return turbo stream for timeline only" do
        get solid_log_ui.streams_path, params: { timeline_only: true }, as: :turbo_stream
        assert_response :success
        assert_equal Mime[:turbo_stream], response.media_type
      end

      test "should return no content when no entries for pagination" do
        # Request entries before ID 1 (should return no results)
        get solid_log_ui.streams_path, params: { before_id: 1 }, as: :turbo_stream
        assert_response :no_content
      end

      test "should handle full refresh with jump to live" do
        get solid_log_ui.streams_path, as: :turbo_stream
        assert_response :success
        assert_equal Mime[:turbo_stream], response.media_type
      end

      test "should filter by request_id" do
        # Create entries with different request_ids
        matching_entry = create_entry(request_id: "req-123", message: "Matching request")
        other_entry = create_entry(request_id: "req-456", message: "Other request")

        get solid_log_ui.streams_path, params: { filters: { request_id: "req-123" } }
        assert_response :success

        assert_equal "req-123", assigns(:current_filters)[:request_id]

        # Verify only entries with req-123 are returned
        entries = assigns(:entries).to_a
        assert_includes entries, matching_entry
        assert_not_includes entries, other_entry
        assert entries.all? { |e| e.request_id == "req-123" }
      end

      test "should filter by job_id" do
        # Create entries with different job_ids
        matching_entry = create_entry(job_id: "job-456", message: "Matching job")
        other_entry = create_entry(job_id: "job-789", message: "Other job")

        get solid_log_ui.streams_path, params: { filters: { job_id: "job-456" } }
        assert_response :success

        assert_equal "job-456", assigns(:current_filters)[:job_id]

        # Verify only entries with job-456 are returned
        entries = assigns(:entries).to_a
        assert_includes entries, matching_entry
        assert_not_includes entries, other_entry
        assert entries.all? { |e| e.job_id == "job-456" }
      end

      test "should filter by duration range" do
        # Create entries with different durations
        fast_entry = create_entry(duration: 5, message: "Fast request")
        medium_entry = create_entry(duration: 50, message: "Medium request")
        slow_entry = create_entry(duration: 150, message: "Slow request")

        get solid_log_ui.streams_path, params: {
          filters: {
            min_duration: "10",
            max_duration: "100"
          }
        }
        assert_response :success

        assert_equal "10", assigns(:current_filters)[:min_duration]
        assert_equal "100", assigns(:current_filters)[:max_duration]

        # Verify only entries within duration range are returned
        entries = assigns(:entries).to_a
        assert_not_includes entries, fast_entry  # 5ms is below min
        assert_includes entries, medium_entry     # 50ms is in range
        assert_not_includes entries, slow_entry   # 150ms is above max
        assert entries.all? { |e| e.duration && e.duration >= 10 && e.duration <= 100 }
      end

      test "should filter by time range" do
        # Create entries at different times
        old_entry = create_entry(timestamp: 3.hours.ago, message: "Old entry")
        recent_entry = create_entry(timestamp: 30.minutes.ago, message: "Recent entry")

        start_time = 1.hour.ago
        end_time = Time.current

        get solid_log_ui.streams_path, params: {
          filters: {
            start_time: start_time.iso8601,
            end_time: end_time.iso8601
          }
        }

        entries = assigns(:entries).to_a
        assert_not_includes entries, old_entry
        assert_includes entries, recent_entry
        assert entries.all? { |e| e.timestamp >= start_time && e.timestamp <= end_time }
      end

      test "should combine multiple filters" do
        # Create entries with various attributes
        matching_entry = create_entry(level: "error", app: "web-app", message: "Matching")
        wrong_level = create_entry(level: "info", app: "web-app", message: "Wrong level")
        wrong_app = create_entry(level: "error", app: "api-app", message: "Wrong app")

        get solid_log_ui.streams_path, params: {
          filters: {
            levels: ["error"],
            app: ["web-app"]
          }
        }

        entries = assigns(:entries).to_a
        assert_includes entries, matching_entry
        assert_not_includes entries, wrong_level
        assert_not_includes entries, wrong_app
        assert entries.all? { |e| e.level == "error" && e.app == "web-app" }
      end

      test "should generate timeline data" do
        get solid_log_ui.streams_path
        assert_response :success
        timeline = assigns(:timeline_data)
        assert timeline.is_a?(Hash)
        assert timeline.key?(:buckets)
      end

      test "should skip timeline for pagination requests" do
        get solid_log_ui.streams_path, params: { after_id: 1 }
        assert_response :success
        assert_equal({ buckets: [] }, assigns(:timeline_data))
      end
    end
  end
end
