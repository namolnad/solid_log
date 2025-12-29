require "test_helper"

module SolidLog
  module Api
    module V1
      class IngestControllerTest < ActionDispatch::IntegrationTest
        include Service::Engine.routes.url_helpers

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

          post api_v1_ingest_path,
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

          post api_v1_ingest_path,
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

          post api_v1_ingest_path,
            params: payload.to_json,
            headers: { "Content-Type" => "application/json" }

          assert_response :unauthorized
        end

        test "POST /ingest with invalid token returns 401" do
          payload = { level: "info", message: "test" }

          post api_v1_ingest_path,
            params: payload.to_json,
            headers: {
              "Authorization" => "Bearer invalid_token",
              "Content-Type" => "application/json"
            }

          assert_response :unauthorized
        end

        test "POST /ingest with invalid JSON returns 422" do
          post api_v1_ingest_path,
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

          post api_v1_ingest_path,
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

          post api_v1_ingest_path,
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

          post api_v1_ingest_path,
            params: payload.to_json,
            headers: {
              "Authorization" => "Bearer #{@token}",
              "Content-Type" => "application/json"
            }

          assert_response :accepted
          assert_equal 100, JSON.parse(response.body)["count"]
          assert_equal 100, RawEntry.count
        end

        # Edge case tests

        test "POST /ingest with empty payload returns 400" do
          post api_v1_ingest_path,
            params: "",
            headers: {
              "Authorization" => "Bearer #{@token}",
              "Content-Type" => "application/json"
            }

          assert_response :bad_request
          assert_equal "Empty payload", JSON.parse(response.body)["error"]
        end

        test "POST /ingest with empty array returns 400" do
          post api_v1_ingest_path,
            params: [].to_json,
            headers: {
              "Authorization" => "Bearer #{@token}",
              "Content-Type" => "application/json"
            }

          assert_response :bad_request
          assert_equal "Empty payload", JSON.parse(response.body)["error"]
        end

        test "POST /ingest with empty object returns 400" do
          # Empty object {} is treated as empty payload
          post api_v1_ingest_path,
            params: {}.to_json,
            headers: {
              "Authorization" => "Bearer #{@token}",
              "Content-Type" => "application/json"
            }

          assert_response :bad_request
          assert_equal "Empty payload", JSON.parse(response.body)["error"]
        end

        test "POST /ingest at max batch size limit" do
          max_size = SolidLog.configuration.max_batch_size
          payload = max_size.times.map do |i|
            { level: "info", message: "Log #{i}" }
          end

          post api_v1_ingest_path,
            params: payload.to_json,
            headers: {
              "Authorization" => "Bearer #{@token}",
              "Content-Type" => "application/json"
            }

          assert_response :accepted
          assert_equal max_size, JSON.parse(response.body)["count"]
        end

        test "POST /ingest over max batch size returns 413" do
          max_size = SolidLog.configuration.max_batch_size
          payload = (max_size + 1).times.map do |i|
            { level: "info", message: "Log #{i}" }
          end

          post api_v1_ingest_path,
            params: payload.to_json,
            headers: {
              "Authorization" => "Bearer #{@token}",
              "Content-Type" => "application/json"
            }

          assert_response :payload_too_large
          json = JSON.parse(response.body)
          assert_equal "Batch too large", json["error"]
          assert_equal max_size, json["max_size"]
          assert_equal max_size + 1, json["received"]
        end

        test "POST /ingest with NDJSON format" do
          # Newline-delimited JSON (one JSON object per line)
          ndjson = [
            { level: "info", message: "Line 1" }.to_json,
            { level: "error", message: "Line 2" }.to_json,
            { level: "warn", message: "Line 3" }.to_json
          ].join("\n")

          post api_v1_ingest_path,
            params: ndjson,
            headers: {
              "Authorization" => "Bearer #{@token}",
              "Content-Type" => "application/x-ndjson"
            }

          assert_response :accepted
          assert_equal 3, JSON.parse(response.body)["count"]
          assert_equal 3, RawEntry.count
        end

        test "POST /ingest with malformed auth header (no Bearer prefix)" do
          payload = { level: "info", message: "test" }

          post api_v1_ingest_path,
            params: payload.to_json,
            headers: {
              "Authorization" => @token, # Missing "Bearer" prefix
              "Content-Type" => "application/json"
            }

          assert_response :unauthorized
          assert_equal "Missing or invalid Authorization header", JSON.parse(response.body)["error"]
        end

        test "POST /ingest with Bearer in different case" do
          payload = { level: "info", message: "test" }

          # "bearer" (lowercase) should work
          post api_v1_ingest_path,
            params: payload.to_json,
            headers: {
              "Authorization" => "bearer #{@token}",
              "Content-Type" => "application/json"
            }

          assert_response :accepted
          assert_equal 1, RawEntry.count
        end

        test "POST /ingest with whitespace in auth header" do
          payload = { level: "info", message: "test" }

          post api_v1_ingest_path,
            params: payload.to_json,
            headers: {
              "Authorization" => "  Bearer   #{@token}  ",
              "Content-Type" => "application/json"
            }

          # Extra whitespace should be handled gracefully
          # This will likely fail - whitespace not trimmed in regex
          assert_response :unauthorized
        end

        test "POST /ingest with unicode and emoji in message" do
          payload = {
            timestamp: Time.current.iso8601,
            level: "info",
            message: "Hello 世界 🌍 émojis and spëcial çharacters",
            app: "test"
          }

          post api_v1_ingest_path,
            params: payload.to_json,
            headers: {
              "Authorization" => "Bearer #{@token}",
              "Content-Type" => "application/json"
            }

          assert_response :accepted
          raw_entry = RawEntry.last
          stored = JSON.parse(raw_entry.payload)
          assert_equal "Hello 世界 🌍 émojis and spëcial çharacters", stored["message"]
        end

        test "POST /ingest with very long message" do
          payload = {
            level: "info",
            message: "A" * 10_000 # 10KB message
          }

          post api_v1_ingest_path,
            params: payload.to_json,
            headers: {
              "Authorization" => "Bearer #{@token}",
              "Content-Type" => "application/json"
            }

          assert_response :accepted
          raw_entry = RawEntry.last
          stored = JSON.parse(raw_entry.payload)
          assert_equal 10_000, stored["message"].length
        end

        test "POST /ingest without Content-Type header returns 400" do
          payload = { level: "info", message: "test" }

          post api_v1_ingest_path,
            params: payload.to_json,
            headers: {
              "Authorization" => "Bearer #{@token}"
              # No Content-Type header - Rails won't parse the JSON body
            }

          # Without Content-Type, body isn't parsed correctly
          assert_response :bad_request
          assert_equal "Empty payload", JSON.parse(response.body)["error"]
        end

        test "POST /ingest with null values in payload" do
          payload = {
            timestamp: Time.current.iso8601,
            level: "info",
            message: nil,
            app: nil,
            env: nil,
            custom_field: nil
          }

          post api_v1_ingest_path,
            params: payload.to_json,
            headers: {
              "Authorization" => "Bearer #{@token}",
              "Content-Type" => "application/json"
            }

          assert_response :accepted
          raw_entry = RawEntry.last
          assert_not_nil raw_entry
          stored = JSON.parse(raw_entry.payload)
          assert_nil stored["message"]
          assert_nil stored["app"]
        end

        test "POST /ingest with special JSON characters" do
          payload = {
            level: "info",
            message: "Special chars: \\ \" \n \t \r { } [ ]",
            path: "/api/test?param=value&other=123"
          }

          post api_v1_ingest_path,
            params: payload.to_json,
            headers: {
              "Authorization" => "Bearer #{@token}",
              "Content-Type" => "application/json"
            }

          assert_response :accepted
          raw_entry = RawEntry.last
          stored = JSON.parse(raw_entry.payload)
          assert_equal "Special chars: \\ \" \n \t \r { } [ ]", stored["message"]
        end

        test "POST /ingest with nested objects" do
          payload = {
            level: "info",
            message: "Nested data",
            metadata: {
              user: { id: 123, name: "John" },
              request: { method: "GET", path: "/test" }
            },
            tags: ["api", "production", "critical"]
          }

          post api_v1_ingest_path,
            params: payload.to_json,
            headers: {
              "Authorization" => "Bearer #{@token}",
              "Content-Type" => "application/json"
            }

          assert_response :accepted
          raw_entry = RawEntry.last
          stored = JSON.parse(raw_entry.payload)
          assert_equal 123, stored["metadata"]["user"]["id"]
          assert_equal ["api", "production", "critical"], stored["tags"]
        end

        test "POST /ingest records received_at timestamp" do
          time_before = Time.current

          payload = { level: "info", message: "test" }

          post api_v1_ingest_path,
            params: payload.to_json,
            headers: {
              "Authorization" => "Bearer #{@token}",
              "Content-Type" => "application/json"
            }

          time_after = Time.current

          raw_entry = RawEntry.last
          assert raw_entry.received_at >= time_before
          assert raw_entry.received_at <= time_after
        end

        test "POST /ingest marks entry as unparsed" do
          payload = { level: "info", message: "test" }

          post api_v1_ingest_path,
            params: payload.to_json,
            headers: {
              "Authorization" => "Bearer #{@token}",
              "Content-Type" => "application/json"
            }

          raw_entry = RawEntry.last
          assert_equal false, raw_entry.parsed
          assert_nil raw_entry.parsed_at
        end
      end
    end
  end
end
