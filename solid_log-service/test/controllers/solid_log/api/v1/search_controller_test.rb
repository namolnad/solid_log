require "test_helper"

module SolidLog
  module Api
    module V1
      class SearchControllerTest < RackTestCase

        setup do
          ENV["SOLIDLOG_SECRET_KEY"] ||= "test-secret-key-for-tests"
          @token_result = Token.generate!("Test API")
          @token = @token_result[:token]

          # Create test entries
          create_entry(level: "info", message: "User successfully logged in")
          create_entry(level: "error", message: "Login failed for user@example.com")
          create_entry(level: "info", message: "Password reset requested")
        end

        test "POST /search with query returns matching entries" do
          post "/api/v1/search",
            { q: "login" }.to_json,
            {
              "HTTP_AUTHORIZATION" => "Bearer #{@token}",
              "CONTENT_TYPE" => "application/json"
            }

          assert_response :success
          json = json_response

          assert_includes json, "entries"
          assert_includes json, "query"
          assert_equal "login", json["query"]
        end

        test "POST /search without query returns 400" do
          post "/api/v1/search",
            {}.to_json,
            {
              "HTTP_AUTHORIZATION" => "Bearer #{@token}",
              "CONTENT_TYPE" => "application/json"
            }

          assert_response :bad_request
          json = json_response
          assert_equal "Query parameter required", json["error"]
        end

        test "POST /search with empty query returns 400" do
          post "/api/v1/search",
            { q: "" }.to_json,
            {
              "HTTP_AUTHORIZATION" => "Bearer #{@token}",
              "CONTENT_TYPE" => "application/json"
            }

          assert_response :bad_request
          assert_equal "Query parameter required", json_response["error"]
        end

        test "POST /search respects limit parameter" do
          post "/api/v1/search",
            { q: "user", limit: 1 }.to_json,
            {
              "HTTP_AUTHORIZATION" => "Bearer #{@token}",
              "CONTENT_TYPE" => "application/json"
            }

          assert_response :success
          json = json_response

          assert json["entries"].size <= 1
          assert_equal 1, json["limit"]
        end

        test "POST /search defaults to limit 100" do
          post "/api/v1/search",
            { q: "test" }.to_json,
            {
              "HTTP_AUTHORIZATION" => "Bearer #{@token}",
              "CONTENT_TYPE" => "application/json"
            }

          assert_response :success
          json = json_response

          assert_equal 100, json["limit"]
        end

        test "POST /search requires authentication" do
          post "/api/v1/search",
            { q: "test" }.to_json,
            { "CONTENT_TYPE" => "application/json" }

          assert_response :unauthorized
        end

        test "POST /search accepts query parameter as alternative to q" do
          post "/api/v1/search",
            { query: "password" }.to_json,
            {
              "HTTP_AUTHORIZATION" => "Bearer #{@token}",
              "CONTENT_TYPE" => "application/json"
            }

          assert_response :success
          json = json_response
          assert_equal "password", json["query"]
        end

        test "POST /search includes total count" do
          post "/api/v1/search",
            { q: "test" }.to_json,
            {
              "HTTP_AUTHORIZATION" => "Bearer #{@token}",
              "CONTENT_TYPE" => "application/json"
            }

          assert_response :success
          json = json_response

          assert_includes json, "total"
          assert_kind_of Integer, json["total"]
        end
      end
    end
  end
end
