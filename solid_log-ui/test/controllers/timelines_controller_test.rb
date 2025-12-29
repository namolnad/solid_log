require "test_helper"

module SolidLog
  module UI
    class TimelinesControllerTest < ActionDispatch::IntegrationTest
      setup do
        @routes = Engine.routes
        @entry_with_request = create_entry(
          level: "error",
          message: "Request failed",
          request_id: "req-timeline-123"
        )
      end

      test "should show request timeline" do
        # Create multiple entries with same request_id at different times
        old_entry = create_entry(
          timestamp: 2.hours.ago,
          request_id: "req-timeline-123",
          message: "Request started"
        )
        middle_entry = create_entry(
          timestamp: 1.hour.ago,
          request_id: "req-timeline-123",
          message: "Processing"
        )

        get solid_log_ui.request_timeline_path(request_id: @entry_with_request.request_id)
        assert_response :success
        assert_equal @entry_with_request.request_id, assigns(:request_id)

        entries = assigns(:entries)
        assert entries.is_a?(ActiveRecord::Relation)

        # Verify all entries have the same request_id
        entries_array = entries.to_a
        assert entries_array.all? { |e| e.request_id == "req-timeline-123" }

        # Verify chronological ordering (oldest first)
        timestamps = entries_array.map(&:timestamp)
        assert_equal timestamps, timestamps.sort
      end

      test "should redirect when no entries for request_id" do
        get solid_log_ui.request_timeline_path(request_id: "nonexistent")
        assert_redirected_to solid_log_ui.streams_path
        assert_match /No entries found/, flash[:alert]
      end

      test "should show job timeline" do
        # Create multiple entries with same job_id at different times
        old_entry = create_entry(
          timestamp: 3.hours.ago,
          level: "info",
          message: "Job started",
          job_id: "job-123"
        )
        middle_entry = create_entry(
          timestamp: 2.hours.ago,
          level: "info",
          message: "Job processing",
          job_id: "job-123"
        )
        new_entry = create_entry(
          timestamp: 1.hour.ago,
          level: "info",
          message: "Job completed",
          job_id: "job-123"
        )

        get solid_log_ui.job_timeline_path(job_id: "job-123")
        assert_response :success
        assert_equal "job-123", assigns(:job_id)

        entries = assigns(:entries)
        assert entries.is_a?(ActiveRecord::Relation)

        # Verify all entries have the same job_id
        entries_array = entries.to_a
        assert entries_array.all? { |e| e.job_id == "job-123" }

        # Verify chronological ordering (oldest first)
        timestamps = entries_array.map(&:timestamp)
        assert_equal timestamps, timestamps.sort
      end

      test "should redirect when no entries for job_id" do
        get solid_log_ui.job_timeline_path(job_id: "nonexistent")
        assert_redirected_to solid_log_ui.streams_path
        assert_match /No entries found/, flash[:alert]
      end
    end
  end
end
