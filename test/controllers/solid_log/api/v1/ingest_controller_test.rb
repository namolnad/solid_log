require "test_helper"

module SolidLog
  module Api
    module V1
      class IngestControllerTest < ActionDispatch::IntegrationTest
        setup do
          @token_result = Token.generate!("Test API")
          @token = @token_result[:token]
        end

        test "POST /ingest with valid token and single entry" do
          payload = {
            timestamp: Time.current.iso8601,
            level: "info",
            message: "Test log message",
            app: "test-app"
          }

          post "/solid_log/api/v1/ingest",
            params: payload.to_json,
            headers: {
              "Authorization" => "Bearer #{@token}",
              "Content-Type" => "application/json"
            }

          assert_response :accepted
          assert_equal "accepted", JSON.parse(response.body)["status"]
          assert_equal 1, JSON.parse(response.body)["count"]
          assert_equal 1, RawEntry.count
        end

        test "POST /ingest with valid token and batch" do
          payload = 3.times.map do |i|
            {
              timestamp: Time.current.iso8601,
              level: "info",
              message: "Test log #{i}"
            }
          end

          post "/solid_log/api/v1/ingest",
            params: payload.to_json,
            headers: {
              "Authorization" => "Bearer #{@token}",
              "Content-Type" => "application/json"
            }

          assert_response :accepted
          assert_equal 3, JSON.parse(response.body)["count"]
          assert_equal 3, RawEntry.count
        end

        test "POST /ingest without auth token returns 401" do
          payload = { level: "info", message: "test" }

          post "/solid_log/api/v1/ingest",
            params: payload.to_json,
            headers: { "Content-Type" => "application/json" }

          assert_response :unauthorized
        end

        test "POST /ingest with invalid token returns 401" do
          payload = { level: "info", message: "test" }

          post "/solid_log/api/v1/ingest",
            params: payload.to_json,
            headers: {
              "Authorization" => "Bearer invalid_token",
              "Content-Type" => "application/json"
            }

          assert_response :unauthorized
        end

        test "POST /ingest with invalid JSON returns 422" do
          post "/solid_log/api/v1/ingest",
            params: "{invalid json",
            headers: {
              "Authorization" => "Bearer #{@token}",
              "Content-Type" => "application/json"
            }

          assert_response :unprocessable_entity
        end

        test "POST /ingest updates token last_used_at" do
          token_record = Token.find(@token_result[:id])
          assert_nil token_record.last_used_at

          payload = { level: "info", message: "test" }

          post "/solid_log/api/v1/ingest",
            params: payload.to_json,
            headers: {
              "Authorization" => "Bearer #{@token}",
              "Content-Type" => "application/json"
            }

          token_record.reload
          assert_not_nil token_record.last_used_at
        end

        test "POST /ingest stores raw payload" do
          payload = {
            timestamp: Time.current.iso8601,
            level: "info",
            message: "test",
            custom_field: "custom_value"
          }

          post "/solid_log/api/v1/ingest",
            params: payload.to_json,
            headers: {
              "Authorization" => "Bearer #{@token}",
              "Content-Type" => "application/json"
            }

          raw_entry = RawEntry.last
          assert_not_nil raw_entry
          stored_payload = JSON.parse(raw_entry.payload)
          assert_equal "test", stored_payload["message"]
          assert_equal "custom_value", stored_payload["custom_field"]
        end

        test "POST /ingest handles large batch" do
          payload = 100.times.map do |i|
            {
              timestamp: Time.current.iso8601,
              level: "info",
              message: "Test log #{i}"
            }
          end

          post "/solid_log/api/v1/ingest",
            params: payload.to_json,
            headers: {
              "Authorization" => "Bearer #{@token}",
              "Content-Type" => "application/json"
            }

          assert_response :accepted
          assert_equal 100, JSON.parse(response.body)["count"]
          assert_equal 100, RawEntry.count
        end
      end
    end
  end
end
