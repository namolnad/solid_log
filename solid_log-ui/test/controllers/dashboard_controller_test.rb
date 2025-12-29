require "test_helper"

module SolidLog
  module UI
    class DashboardControllerTest < ActionDispatch::IntegrationTest
      setup do
        @routes = Engine.routes
      end

      test "should get index" do
        get solid_log_ui.dashboard_path
        assert_response :success
      end

      test "should display health metrics" do
        get solid_log_ui.dashboard_path
        assert_response :success
        assert_select "h1", text: /Dashboard/i
      end

      test "should load recent errors" do
        # Create mix of log levels
        info_entry = create_entry(level: "info", message: "Info log")
        warn_entry = create_entry(level: "warn", message: "Warning log")
        error_entry = create_entry(level: "error", message: "Error log")
        fatal_entry = create_entry(level: "fatal", message: "Fatal log")

        get solid_log_ui.dashboard_path
        assert_response :success

        recent_errors = assigns(:recent_errors).to_a

        # Should only include error and fatal, not info or warn
        assert_includes recent_errors, error_entry
        assert_includes recent_errors, fatal_entry
        assert_not_includes recent_errors, info_entry
        assert_not_includes recent_errors, warn_entry

        # Verify all entries are actually errors or fatal
        assert recent_errors.all? { |e| e.level.in?(%w[error fatal]) }
      end

      test "should load log level distribution" do
        # Create entries with specific levels
        3.times { create_entry(level: "info") }
        2.times { create_entry(level: "error") }
        1.times { create_entry(level: "warn") }

        get solid_log_ui.dashboard_path
        assert_response :success

        distribution = assigns(:log_level_distribution)

        # Should be a hash with level counts
        assert distribution.is_a?(Hash)
        assert_equal 3, distribution["info"]
        assert_equal 2, distribution["error"]
        assert_equal 1, distribution["warn"]
      end

      test "should load field recommendations" do
        # Create fields with different usage counts to get recommendations
        create_field(name: "high_usage_field", usage_count: 2000, last_seen_at: Time.current)
        create_field(name: "medium_usage_field", usage_count: 1500, last_seen_at: Time.current)

        get solid_log_ui.dashboard_path
        assert_response :success

        recommendations = assigns(:field_recommendations)

        # Should be an array
        assert recommendations.is_a?(Array)

        # Should contain recommendation hashes with expected keys
        if recommendations.any?
          recommendation = recommendations.first
          assert recommendation.is_a?(Hash)
          assert recommendation.key?(:field)
          assert recommendation.key?(:priority)
          assert recommendation.key?(:reason)
        end
      end

      test "should limit recent errors to 10" do
        # Create more than 10 errors
        15.times { |i| create_entry(level: "error", message: "Error #{i}") }

        get solid_log_ui.dashboard_path
        recent_errors = assigns(:recent_errors).to_a

        assert_equal 10, recent_errors.size
      end

      test "recent errors should be ordered chronologically (oldest first)" do
        old_error = create_entry(level: "error", timestamp: 2.hours.ago, message: "Old error")
        new_error = create_entry(level: "error", timestamp: 1.hour.ago, message: "New error")

        get solid_log_ui.dashboard_path
        recent_errors = assigns(:recent_errors).to_a

        # Recent scope orders ascending (terminal-style: newest at bottom)
        assert_equal 2, recent_errors.size
        assert recent_errors.first.timestamp < recent_errors.last.timestamp,
               "Expected chronological order (oldest first)"
      end
    end
  end
end
