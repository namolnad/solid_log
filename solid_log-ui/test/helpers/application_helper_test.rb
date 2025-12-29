require "test_helper"

module SolidLog
  module UI
    class ApplicationHelperTest < ActionView::TestCase
      include SolidLog::UI::Engine.routes.url_helpers

      test "level_badge returns correct class for debug" do
        result = level_badge("debug")
        assert_match /badge-gray/, result
        assert_match /DEBUG/, result
      end

      test "level_badge returns correct class for info" do
        result = level_badge("info")
        assert_match /badge-blue/, result
        assert_match /INFO/, result
      end

      test "level_badge returns correct class for warn" do
        result = level_badge("warn")
        assert_match /badge-yellow/, result
        assert_match /WARN/, result
      end

      test "level_badge returns correct class for error" do
        result = level_badge("error")
        assert_match /badge-red/, result
        assert_match /ERROR/, result
      end

      test "level_badge returns correct class for fatal" do
        result = level_badge("fatal")
        assert_match /badge-dark-red/, result
        assert_match /FATAL/, result
      end

      test "level_badge returns secondary class for unknown level" do
        result = level_badge("unknown")
        assert_match /badge-secondary/, result
      end

      test "http_status_badge returns success for 2xx" do
        result = http_status_badge(200)
        assert_match /badge-success/, result
        assert_match /200/, result
      end

      test "http_status_badge returns info for 3xx" do
        result = http_status_badge(301)
        assert_match /badge-info/, result
      end

      test "http_status_badge returns warning for 4xx" do
        result = http_status_badge(404)
        assert_match /badge-warning/, result
      end

      test "http_status_badge returns danger for 5xx" do
        result = http_status_badge(500)
        assert_match /badge-danger/, result
      end

      test "http_status_badge returns empty string for blank" do
        assert_equal "", http_status_badge(nil)
        assert_equal "", http_status_badge("")
      end

      test "format_duration formats milliseconds" do
        assert_equal "150.0ms", format_duration(150)
        assert_equal "999.0ms", format_duration(999)
      end

      test "format_duration formats seconds" do
        assert_equal "1.5s", format_duration(1500)
        assert_equal "2.5s", format_duration(2500)
      end

      test "format_duration returns empty for blank" do
        assert_equal "", format_duration(nil)
        assert_equal "", format_duration("")
      end

      test "truncate_message truncates long messages" do
        long_message = "a" * 300
        result = truncate_message(long_message, length: 100)
        assert result.length <= 103 # 100 + "..."
      end

      test "truncate_message returns empty for blank" do
        assert_equal "", truncate_message(nil)
        assert_equal "", truncate_message("")
      end

      test "highlight_search_term highlights query" do
        text = "This is a test message"
        result = highlight_search_term(text, "test")
        assert_match /<mark>test<\/mark>/, result
      end

      test "highlight_search_term returns text when query blank" do
        text = "This is a test message"
        assert_equal text, highlight_search_term(text, nil)
        assert_equal text, highlight_search_term(text, "")
      end

      test "correlation_link generates request link" do
        entry = create_entry(
          level: "error",
          message: "Error with request",
          request_id: "req-correlation-123"
        )
        result = correlation_link(entry)
        assert_match /Request:/, result
        assert_match /#{entry.request_id[0..7]}/, result
      end

      test "correlation_link returns empty for uncorrelated entry" do
        entry = create_entry(
          level: "debug",
          message: "Debug message",
          request_id: nil,
          job_id: nil
        )
        result = correlation_link(entry)
        assert_equal "", result
      end
    end
  end
end
