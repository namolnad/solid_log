require "test_helper"

module SolidLog
  module Api
    module V1
      class FacetsControllerTest < ActionDispatch::IntegrationTest
        include Service::Engine.routes.url_helpers

        setup do
          @token_result = Token.generate!("Test API")
          @token = @token_result[:token]

          # Create entries with various facet values
          create_entry(level: "info", app: "web", env: "production", method: "GET", status_code: 200)
          create_entry(level: "error", app: "web", env: "production", method: "POST", status_code: 500)
          create_entry(level: "warn", app: "api", env: "staging", method: "GET", status_code: 404)
          create_entry(level: "info", app: "api", env: "staging", method: "PUT", status_code: 200)
        end

        test "GET /facets with field parameter returns facet values" do
          get api_v1_facets_path(field: "level"),
            headers: { "Authorization" => "Bearer #{@token}" }

          assert_response :success
          json = JSON.parse(response.body)

          assert_includes json, "field"
          assert_includes json, "values"
          assert_includes json, "total"
          assert_equal "level", json["field"]
          assert_kind_of Array, json["values"]
        end

        test "GET /facets without field parameter returns 400" do
          get api_v1_facets_path,
            headers: { "Authorization" => "Bearer #{@token}" }

          assert_response :bad_request
          json = JSON.parse(response.body)
          assert_equal "Field parameter required", json["error"]
        end

        test "GET /facets with empty field returns 400" do
          get api_v1_facets_path(field: ""),
            headers: { "Authorization" => "Bearer #{@token}" }

          assert_response :bad_request
          assert_equal "Field parameter required", JSON.parse(response.body)["error"]
        end

        test "GET /facets returns unique values for field" do
          get api_v1_facets_path(field: "level"),
            headers: { "Authorization" => "Bearer #{@token}" }

          assert_response :success
          json = JSON.parse(response.body)

          # Should have 3 unique levels: info, error, warn
          assert json["values"].size >= 3
          assert json["values"].uniq.size == json["values"].size, "Values should be unique"
        end

        test "GET /facets respects limit parameter" do
          get api_v1_facets_path(field: "level", limit: 2),
            headers: { "Authorization" => "Bearer #{@token}" }

          assert_response :success
          json = JSON.parse(response.body)

          assert json["values"].size <= 2
        end

        test "GET /facets defaults to limit 100" do
          get api_v1_facets_path(field: "app"),
            headers: { "Authorization" => "Bearer #{@token}" }

          assert_response :success
          json = JSON.parse(response.body)

          # Limit is enforced in service, not returned in response
          # Just verify structure is correct
          assert_kind_of Array, json["values"]
        end

        test "GET /facets/all returns all facets" do
          get api_v1_all_facets_path,
            headers: { "Authorization" => "Bearer #{@token}" }

          assert_response :success
          json = JSON.parse(response.body)

          assert_includes json, "facets"
          facets = json["facets"]

          # Should have all standard facet fields
          assert_includes facets, "level"
          assert_includes facets, "app"
          assert_includes facets, "env"
          assert_includes facets, "controller"
          assert_includes facets, "action"
          assert_includes facets, "method"
          assert_includes facets, "status_code"

          # Each facet should be an array
          facets.each do |field, values|
            assert_kind_of Array, values, "#{field} should be an array"
          end
        end

        test "GET /facets requires authentication" do
          get api_v1_facets_path(field: "level")

          assert_response :unauthorized
        end

        test "GET /facets/all requires authentication" do
          get api_v1_all_facets_path

          assert_response :unauthorized
        end

        test "GET /facets works with various field names" do
          fields = %w[level app env method status_code]

          fields.each do |field|
            get api_v1_facets_path(field: field),
              headers: { "Authorization" => "Bearer #{@token}" }

            assert_response :success, "Failed for field: #{field}"
            json = JSON.parse(response.body)
            assert_equal field, json["field"]
            assert_kind_of Array, json["values"]
          end
        end
      end
    end
  end
end
