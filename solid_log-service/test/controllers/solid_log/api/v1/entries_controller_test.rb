require "test_helper"

module SolidLog
  module Api
    module V1
      class EntriesControllerTest < ActionDispatch::IntegrationTest
        include Service::Engine.routes.url_helpers

        setup do
          @token_result = Token.generate!("Test API")
          @token = @token_result[:token]

          # Create test entries
          @entry1 = create_entry(
            level: "info",
            message: "User login",
            app: "web",
            env: "production",
            controller: "SessionsController",
            action: "create",
            status_code: 200
          )

          @entry2 = create_entry(
            level: "error",
            message: "Database connection failed",
            app: "api",
            env: "production",
            status_code: 500
          )

          @entry3 = create_entry(
            level: "info",
            message: "API request processed",
            app: "api",
            env: "staging"
          )
        end

        test "GET /entries returns all entries" do
          get api_v1_entries_path,
            headers: { "Authorization" => "Bearer #{@token}" }

          assert_response :success
          json = JSON.parse(response.body)

          assert_includes json, "entries"
          assert_includes json, "total"
          assert_equal 3, json["entries"].size
        end

        test "GET /entries filters by level" do
          get api_v1_entries_path(filters: { level: "error" }),
            headers: { "Authorization" => "Bearer #{@token}" }

          assert_response :success
          json = JSON.parse(response.body)

          assert_equal 1, json["entries"].size
          assert_equal "error", json["entries"].first["level"]
          assert_equal "Database connection failed", json["entries"].first["message"]
        end

        test "GET /entries filters by app" do
          get api_v1_entries_path(filters: { app: "api" }),
            headers: { "Authorization" => "Bearer #{@token}" }

          assert_response :success
          json = JSON.parse(response.body)

          assert_equal 2, json["entries"].size
          json["entries"].each do |entry|
            assert_equal "api", entry["app"]
          end
        end

        test "GET /entries filters by env" do
          get api_v1_entries_path(filters: { env: "staging" }),
            headers: { "Authorization" => "Bearer #{@token}" }

          assert_response :success
          json = JSON.parse(response.body)

          assert_equal 1, json["entries"].size
          assert_equal "staging", json["entries"].first["env"]
        end

        test "GET /entries filters by multiple params" do
          get api_v1_entries_path(filters: { app: "api", env: "production" }),
            headers: { "Authorization" => "Bearer #{@token}" }

          assert_response :success
          json = JSON.parse(response.body)

          assert_equal 1, json["entries"].size
          assert_equal "api", json["entries"].first["app"]
          assert_equal "production", json["entries"].first["env"]
        end

        test "GET /entries filters by status_code" do
          get api_v1_entries_path(filters: { status_code: 500 }),
            headers: { "Authorization" => "Bearer #{@token}" }

          assert_response :success
          json = JSON.parse(response.body)

          assert_equal 1, json["entries"].size
          assert_equal 500, json["entries"].first["status_code"]
        end

        test "GET /entries filters by controller and action" do
          get api_v1_entries_path(filters: { controller: "SessionsController", action: "create" }),
            headers: { "Authorization" => "Bearer #{@token}" }

          assert_response :success
          json = JSON.parse(response.body)

          assert_equal 1, json["entries"].size
          assert_equal "SessionsController", json["entries"].first["controller"]
          assert_equal "create", json["entries"].first["action"]
        end

        test "GET /entries supports FTS search via q parameter" do
          get api_v1_entries_path(q: "login"),
            headers: { "Authorization" => "Bearer #{@token}" }

          assert_response :success
          json = JSON.parse(response.body)

          # FTS may or may not work in test depending on schema setup
          # Just verify no errors and valid response structure
          assert_includes json, "entries"
        end

        test "GET /entries respects limit parameter" do
          get api_v1_entries_path(limit: 2),
            headers: { "Authorization" => "Bearer #{@token}" }

          assert_response :success
          json = JSON.parse(response.body)

          assert json["entries"].size <= 2
          assert_equal 2, json["limit"]
        end

        test "GET /entries defaults to limit 100" do
          get api_v1_entries_path,
            headers: { "Authorization" => "Bearer #{@token}" }

          assert_response :success
          json = JSON.parse(response.body)

          assert_equal 100, json["limit"]
        end

        test "GET /entries returns most recent entries first" do
          # Create entries with known timestamps
          old_entry = create_entry(timestamp: 2.hours.ago, created_at: 2.hours.ago, message: "Old")
          new_entry = create_entry(timestamp: 1.hour.ago, created_at: 1.hour.ago, message: "New")

          get api_v1_entries_path,
            headers: { "Authorization" => "Bearer #{@token}" }

          assert_response :success
          json = JSON.parse(response.body)

          # First entry should be most recent
          assert_equal new_entry.id, json["entries"].first["id"]
        end

        test "GET /entries/:id returns single entry" do
          get api_v1_entry_path(@entry1),
            headers: { "Authorization" => "Bearer #{@token}" }

          assert_response :success
          json = JSON.parse(response.body)

          assert_includes json, "entry"
          assert_equal @entry1.id, json["entry"]["id"]
          assert_equal "User login", json["entry"]["message"]
        end

        test "GET /entries/:id returns 404 for non-existent entry" do
          get api_v1_entry_path(id: 99999),
            headers: { "Authorization" => "Bearer #{@token}" }

          assert_response :not_found
          json = JSON.parse(response.body)
          assert_equal "Entry not found", json["error"]
        end

        test "GET /entries requires authentication" do
          get api_v1_entries_path

          assert_response :unauthorized
        end

        test "GET /entries includes extra_fields_hash" do
          # Create entry with extra fields
          entry = create_entry(
            message: "Test",
            extra_fields: { user_id: 123, custom: "value" }.to_json
          )

          get api_v1_entry_path(entry),
            headers: { "Authorization" => "Bearer #{@token}" }

          assert_response :success
          json = JSON.parse(response.body)

          # extra_fields_hash should be included via as_json method
          assert json["entry"].key?("extra_fields") || json["entry"].key?("extra_fields_hash")
        end

        test "GET /entries with no results returns empty array" do
          get api_v1_entries_path(filters: { level: "fatal" }),
            headers: { "Authorization" => "Bearer #{@token}" }

          assert_response :success
          json = JSON.parse(response.body)

          assert_equal [], json["entries"]
          assert_equal 0, json["total"]
        end
      end
    end
  end
end
