require "test_helper"

module SolidLog
  module UI
    class EntriesControllerTest < ActionDispatch::IntegrationTest
      setup do
        @routes = Engine.routes
        @entry = create_entry(
          level: "error",
          message: "Database connection failed",
          request_id: "req-123"
        )
      end

      test "should redirect index to streams" do
        get solid_log_ui.entries_path
        assert_redirected_to solid_log_ui.streams_path
      end

      test "should show entry" do
        get solid_log_ui.entry_path(@entry)
        assert_response :success
        assert_equal @entry, assigns(:entry)
      end

      test "should load correlated entries for request_id" do
        entry_with_request = create_entry(
          level: "error",
          message: "Query error",
          request_id: "req-456"
        )
        # Create correlated entries with same request_id
        correlated_entry1 = create_entry(
          level: "info",
          message: "Request started",
          request_id: "req-456"
        )
        correlated_entry2 = create_entry(
          level: "debug",
          message: "Processing request",
          request_id: "req-456"
        )
        # Create an unrelated entry with different request_id
        unrelated_entry = create_entry(
          level: "info",
          message: "Other request",
          request_id: "req-999"
        )

        get solid_log_ui.entry_path(entry_with_request)
        assert_response :success

        correlated = assigns(:correlated_entries)
        assert correlated.is_a?(ActiveRecord::Relation)

        # Verify only entries with matching request_id are included (excluding the entry itself)
        correlated_array = correlated.to_a
        assert_includes correlated_array, correlated_entry1
        assert_includes correlated_array, correlated_entry2
        assert_not_includes correlated_array, entry_with_request # Should not include itself
        assert_not_includes correlated_array, unrelated_entry

        # Verify all correlated entries have the same request_id
        assert correlated_array.all? { |e| e.request_id == "req-456" }
      end

      test "should load correlated entries for job_id" do
        entry_with_job = create_entry(
          level: "error",
          message: "Job failed",
          job_id: "job-789"
        )
        # Create correlated entries with same job_id
        correlated_entry = create_entry(
          level: "info",
          message: "Job started",
          job_id: "job-789"
        )
        # Create an unrelated entry with different job_id
        unrelated_entry = create_entry(
          level: "info",
          message: "Other job",
          job_id: "job-111"
        )

        get solid_log_ui.entry_path(entry_with_job)
        assert_response :success

        correlated = assigns(:correlated_entries).to_a
        assert_includes correlated, correlated_entry
        assert_not_includes correlated, entry_with_job # Should not include itself
        assert_not_includes correlated, unrelated_entry

        # Verify all correlated entries have the same job_id
        assert correlated.all? { |e| e.job_id == "job-789" }
      end

      test "should not load correlated entries when none exist" do
        entry_without_correlation = create_entry(
          level: "debug",
          message: "Debug message",
          request_id: nil,
          job_id: nil
        )
        get solid_log_ui.entry_path(entry_without_correlation)
        assert_response :success
        assert_nil assigns(:correlated_entries)
      end

      test "should limit correlated entries" do
        entry_with_request = create_entry(
          level: "error",
          message: "Main entry",
          request_id: "req-many"
        )
        # Create more than 50 correlated entries (controller limits to 50)
        60.times do |i|
          create_entry(
            level: "info",
            message: "Correlated #{i}",
            request_id: "req-many"
          )
        end

        get solid_log_ui.entry_path(entry_with_request)
        correlated = assigns(:correlated_entries).to_a

        # Should be limited to 50 (not including the entry itself)
        assert correlated.size <= 50
      end

      test "should return not found for invalid entry" do
        get solid_log_ui.entry_path(id: 999999)
        assert_response :not_found
      end
    end
  end
end
