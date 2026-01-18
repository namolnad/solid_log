require "test_helper"

module SolidLog
  module UI
    class DashboardHelperTest < ActionView::TestCase
      test "format_count formats number with delimiter" do
        assert_equal "1,000", format_count(1000)
        assert_equal "1,000,000", format_count(1_000_000)
      end

      test "format_count handles zero" do
        assert_equal "0", format_count(0)
      end

      test "format_count handles nil" do
        assert_equal "0", format_count(nil)
      end

      test "format_percentage calculates percentage" do
        assert_equal "50.0%", format_percentage(50, 100)
        assert_equal "25.0%", format_percentage(25, 100)
      end

      test "format_percentage handles zero denominator" do
        assert_equal "0%", format_percentage(50, 0)
      end

      test "format_percentage handles nil denominator" do
        assert_equal "0%", format_percentage(50, nil)
      end

      test "trend_indicator shows positive trend" do
        result = trend_indicator(120, 100)
        assert_match /\+20.0%/, result
        assert_match /trend-up/, result
      end

      test "trend_indicator shows negative trend" do
        result = trend_indicator(80, 100)
        assert_match /-20.0%/, result
        assert_match /trend-down/, result
      end

      test "trend_indicator shows neutral trend" do
        result = trend_indicator(100, 100)
        assert_match /0%/, result
        assert_match /trend-neutral/, result
      end

      test "trend_indicator returns empty for nil previous" do
        assert_equal "", trend_indicator(100, nil)
      end

      test "trend_indicator returns empty for zero previous" do
        assert_equal "", trend_indicator(100, 0)
      end

      test "time_ago_or_never formats time" do
        time = 2.hours.ago
        result = time_ago_or_never(time)
        assert_match /ago$/, result
      end

      test "time_ago_or_never returns Never for nil" do
        assert_equal "Never", time_ago_or_never(nil)
      end

      test "health_status_badge returns Healthy for zero unparsed" do
        result = health_status_badge(0)
        assert_match /Healthy/, result
        assert_match /badge-success/, result
      end

      test "health_status_badge returns OK for low unparsed" do
        result = health_status_badge(50)
        assert_match /OK/, result
        assert_match /badge-info/, result
      end

      test "health_status_badge returns Warning for medium unparsed" do
        result = health_status_badge(500)
        assert_match /Warning/, result
        assert_match /badge-warning/, result
      end

      test "health_status_badge returns Backlog for high unparsed" do
        result = health_status_badge(1500)
        assert_match /Backlog/, result
        assert_match /badge-danger/, result
      end
    end
  end
end
