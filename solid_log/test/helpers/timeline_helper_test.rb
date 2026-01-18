require "test_helper"

module SolidLog
  module UI
    class TimelineHelperTest < ActionView::TestCase
      test "timeline_duration_bar calculates width percentage" do
        result = timeline_duration_bar(50, 100)
        assert_match /width: 50.0%/, result
        assert_match /timeline-duration-bar/, result
      end

      test "timeline_duration_bar caps at 100%" do
        result = timeline_duration_bar(150, 100)
        assert_match /width: 100.0%/, result
      end

      test "timeline_duration_bar returns empty for nil duration" do
        assert_equal "", timeline_duration_bar(nil, 100)
      end

      test "timeline_duration_bar returns empty for zero max" do
        assert_equal "", timeline_duration_bar(50, 0)
      end

      test "format_timeline_duration formats sub-millisecond" do
        assert_equal "< 1ms", format_timeline_duration(0.5)
      end

      test "format_timeline_duration formats milliseconds" do
        assert_equal "100.0ms", format_timeline_duration(100)
        assert_equal "999.0ms", format_timeline_duration(999)
      end

      test "format_timeline_duration formats seconds" do
        assert_equal "1.0s", format_timeline_duration(1000)
        assert_equal "2.5s", format_timeline_duration(2500)
      end

      test "format_timeline_duration returns N/A for nil" do
        assert_equal "N/A", format_timeline_duration(nil)
      end

      test "timeline_event_icon returns correct icon for error" do
        entry = create_entry(level: "error", message: "Error occurred")
        assert_equal "⚠️", timeline_event_icon(entry)
      end

      test "timeline_event_icon returns correct icon for warn" do
        entry = create_entry(level: "warn", message: "Warning occurred")
        assert_equal "⚡", timeline_event_icon(entry)
      end

      test "timeline_event_icon returns correct icon for info" do
        entry = create_entry(level: "info", message: "Info message")
        assert_equal "ℹ️", timeline_event_icon(entry)
      end

      test "timeline_event_icon returns correct icon for debug" do
        entry = create_entry(level: "debug", message: "Debug message")
        assert_equal "🔍", timeline_event_icon(entry)
      end

      test "timeline_event_icon returns dot for unknown level" do
        entry = Entry.new(level: "unknown")
        assert_equal "•", timeline_event_icon(entry)
      end
    end
  end
end
