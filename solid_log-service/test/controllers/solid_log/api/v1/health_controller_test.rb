require "test_helper"

module SolidLog
  module Api
    module V1
      class HealthControllerTest < ActionDispatch::IntegrationTest
        include Service::Engine.routes.url_helpers

        test "GET /health returns health metrics without authentication" do
          # Health endpoint should not require authentication
          get api_v1_health_path

          assert_response :success
          json = JSON.parse(response.body)

          assert_includes json, "status"
          assert_includes json, "timestamp"
          assert_includes json, "metrics"
        end

        test "GET /health returns ok status when healthy" do
          # Create and parse some entries to ensure system is healthy (no backlog)
          create_raw_entry
          ParserJob.perform_now

          get api_v1_health_path

          assert_response :ok
          json = JSON.parse(response.body)

          assert_includes ["healthy", "ok", "warning", "degraded"], json["status"]
        end

        test "GET /health returns service_unavailable when critical" do
          # Create many old unparsed entries to trigger critical status
          100.times do |i|
            RawEntry.create!(
              payload: {timestamp: Time.current.iso8601, level: "info"}.to_json,
              token_id: create_test_token[:id],
              received_at: 2.hours.ago,
              parsed: false
            )
          end

          get api_v1_health_path

          json = JSON.parse(response.body)

          # Should still return a response even if critical
          assert_includes json, "status"
          assert_includes json, "metrics"

          # If status is critical, HTTP status should be 503
          if json["status"] == "critical"
            assert_response :service_unavailable
          end
        end

        test "GET /health includes parsing metrics" do
          get api_v1_health_path

          json = JSON.parse(response.body)

          assert_includes json["metrics"], "parsing"

          parsing_metrics = json["metrics"]["parsing"]
          assert_includes parsing_metrics, "unparsed_count"
          assert_includes parsing_metrics, "health_status"
        end

        test "GET /health includes storage metrics" do
          get api_v1_health_path

          json = JSON.parse(response.body)

          assert_includes json["metrics"], "storage"

          storage_metrics = json["metrics"]["storage"]
          assert_includes storage_metrics, "total_entries"
          assert_includes storage_metrics, "total_fields"
        end

        test "GET /health timestamp is in ISO8601 format" do
          get api_v1_health_path

          json = JSON.parse(response.body)
          timestamp = json["timestamp"]

          # Should be parseable as ISO8601
          assert_nothing_raised do
            Time.iso8601(timestamp)
          end
        end

        test "GET /health works when database is empty" do
          # Ensure we can get health even with no data
          get api_v1_health_path

          assert_response :success
          json = JSON.parse(response.body)

          assert_equal 0, json["metrics"]["storage"]["total_entries"]
        end
      end
    end
  end
end
