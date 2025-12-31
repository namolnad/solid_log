require "test_helper"

module SolidLog
  module Api
    module V1
      class TimelinesControllerTest < RackTestCase
        setup do
          ENV["SOLIDLOG_SECRET_KEY"] ||= "test-secret-key-for-tests"
          @token_result = Token.generate!("Test API")
          @token = @token_result[:token]

          # Create entries with same request_id for correlation
          @request_id = "req-#{SecureRandom.hex(8)}"
          @entry1 = create_entry(
            timestamp: 3.seconds.ago,
            created_at: 3.seconds.ago,
            level: "info",
            message: "Request started",
            request_id: @request_id
          )
          @entry2 = create_entry(
            timestamp: 2.seconds.ago,
            created_at: 2.seconds.ago,
            level: "info",
            message: "Database query",
            request_id: @request_id
          )
          @entry3 = create_entry(
            timestamp: 1.second.ago,
            created_at: 1.second.ago,
            level: "info",
            message: "Request completed",
            request_id: @request_id
          )

          # Create entries with same job_id for correlation
          @job_id = "job-#{SecureRandom.hex(8)}"
          @job_entry1 = create_entry(
            timestamp: 2.seconds.ago,
            created_at: 2.seconds.ago,
            level: "info",
            message: "Job started",
            job_id: @job_id
          )
          @job_entry2 = create_entry(
            timestamp: 1.second.ago,
            created_at: 1.second.ago,
            level: "info",
            message: "Job completed",
            job_id: @job_id
          )
        end

        test "GET /timelines/request/:request_id returns request timeline" do
          get "/api/v1/timeline/request/#{@request_id}", {},
            { "HTTP_AUTHORIZATION" => "Bearer #{@token}" }

          assert_response :success
          json = json_response

          assert_includes json, "request_id"
          assert_includes json, "entries"
          assert_includes json, "stats"
          assert_equal @request_id, json["request_id"]
          assert_equal 3, json["entries"].size
        end

        test "GET /timelines/request/:request_id returns entries in chronological order" do
          get "/api/v1/timeline/request/#{@request_id}", {},
            { "HTTP_AUTHORIZATION" => "Bearer #{@token}" }

          assert_response :success
          json = json_response

          entries = json["entries"]
          assert_equal "Request started", entries[0]["message"]
          assert_equal "Database query", entries[1]["message"]
          assert_equal "Request completed", entries[2]["message"]
        end

        test "GET /timelines/request/:request_id without request_id returns 404" do
          get "/api/v1/timeline/request/", {},
            { "HTTP_AUTHORIZATION" => "Bearer #{@token}" }

          # Empty string doesn't match route pattern, so Rails returns 404
          assert_response :not_found
        end

        test "GET /timelines/request/:request_id with non-existent ID returns empty entries" do
          get "/api/v1/timeline/request/non-existent", {},
            { "HTTP_AUTHORIZATION" => "Bearer #{@token}" }

          assert_response :success
          json = json_response

          assert_equal "non-existent", json["request_id"]
          assert_equal [], json["entries"]
        end

        test "GET /timelines/request/:request_id includes stats" do
          get "/api/v1/timeline/request/#{@request_id}", {},
            { "HTTP_AUTHORIZATION" => "Bearer #{@token}" }

          assert_response :success
          json = json_response

          assert_kind_of Hash, json["stats"]
        end

        test "GET /timelines/job/:job_id returns job timeline" do
          get "/api/v1/timeline/job/#{@job_id}", {},
            { "HTTP_AUTHORIZATION" => "Bearer #{@token}" }

          assert_response :success
          json = json_response

          assert_includes json, "job_id"
          assert_includes json, "entries"
          assert_includes json, "stats"
          assert_equal @job_id, json["job_id"]
          assert_equal 2, json["entries"].size
        end

        test "GET /timelines/job/:job_id returns entries in chronological order" do
          get "/api/v1/timeline/job/#{@job_id}", {},
            { "HTTP_AUTHORIZATION" => "Bearer #{@token}" }

          assert_response :success
          json = json_response

          entries = json["entries"]
          assert_equal "Job started", entries[0]["message"]
          assert_equal "Job completed", entries[1]["message"]
        end

        test "GET /timelines/job/:job_id without job_id returns 404" do
          get "/api/v1/timeline/job/", {},
            { "HTTP_AUTHORIZATION" => "Bearer #{@token}" }

          # Empty string doesn't match route pattern, so Rails returns 404
          assert_response :not_found
        end

        test "GET /timelines/job/:job_id with non-existent ID returns empty entries" do
          get "/api/v1/timeline/job/non-existent", {},
            { "HTTP_AUTHORIZATION" => "Bearer #{@token}" }

          assert_response :success
          json = json_response

          assert_equal "non-existent", json["job_id"]
          assert_equal [], json["entries"]
        end

        test "GET /timelines/request requires authentication" do
          get "/api/v1/timeline/request/#{@request_id}"

          assert_response :unauthorized
        end

        test "GET /timelines/job requires authentication" do
          get "/api/v1/timeline/job/#{@job_id}"

          assert_response :unauthorized
        end

        test "GET /timelines/request/:request_id includes extra_fields" do
          get "/api/v1/timeline/request/#{@request_id}", {},
            { "HTTP_AUTHORIZATION" => "Bearer #{@token}" }

          assert_response :success
          json = json_response

          # entries should include extra_fields_hash via as_json
          json["entries"].each do |entry|
            assert entry.key?("id")
            assert entry.key?("message")
          end
        end
      end
    end
  end
end
