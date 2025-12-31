require "rack"
require "json"

module SolidLog
  module Service
    class RackApp
      def call(env)
        request = Rack::Request.new(env)
        method = request.request_method
        path = request.path_info

        # Route matching
        route(method, path, request)
      rescue JSON::ParserError => e
        bad_request("Invalid JSON: #{e.message}")
      rescue ActiveRecord::RecordInvalid => e
        unprocessable_entity("Validation error", e.record.errors.full_messages)
      rescue => e
        internal_error(e)
      end

      private

      # Router - matches HTTP method and path to handler using pattern matching
      def route(method, path, request)
        # Split path into segments for easier matching
        segments = path.split("/").reject(&:empty?)

        # Pattern match on [method, segments]
        case [method, segments]
        # POST routes
        in ["POST", ["api", "v1", "ingest"]]
          handle_ingest(request)
        in ["POST", ["api", "v1", "search"]]
          handle_search(request)

        # GET routes - static
        in ["GET", ["api", "v1", "entries"]]
          handle_entries_index(request)
        in ["GET", ["api", "v1", "facets"]]
          handle_facets(request)
        in ["GET", ["api", "v1", "facets", "all"]]
          handle_facets_all(request)
        in ["GET", ["health"]] | ["GET", ["api", "v1", "health"]]
          handle_health(request)
        in ["GET", ["cable"]]
          ActionCable.server.call(request.env)

        # GET routes - with parameters
        in ["GET", ["api", "v1", "entries", id]]
          handle_entries_show(request, id)
        in ["GET", ["api", "v1", "timeline", "request", request_id]]
          handle_timeline_request(request, request_id)
        in ["GET", ["api", "v1", "timeline", "job", job_id]]
          handle_timeline_job(request, job_id)

        else
          not_found
        end
      end

      # POST /api/v1/ingest
      def handle_ingest(request)
        token = authenticate!(request)
        return token unless token.is_a?(SolidLog::Token)

        payload = parse_ingest_payload(request)

        if payload.blank?
          return bad_request("Empty payload")
        end

        entries = Array.wrap(payload)

        max = SolidLog.configuration.max_batch_size
        if entries.size > max
          return response(413, {
            error: "Batch too large",
            max_size: max,
            received: entries.size
          })
        end

        # Create raw entries
        raw_entries = entries.map do |entry|
          {
            token_id: token.id,
            payload: entry.to_json,
            received_at: Time.current,
            parsed: false
          }
        end

        # Bulk insert
        SolidLog.without_logging do
          SolidLog::RawEntry.insert_all(raw_entries)
        end

        token.touch_last_used!

        response(202, {
          status: "accepted",
          count: entries.size,
          message: "Log entries queued for processing"
        })
      end

      # GET /api/v1/entries
      def handle_entries_index(request)
        token = authenticate!(request)
        return token unless token.is_a?(SolidLog::Token)

        search_params = build_filter_params(request)
        search_service = SolidLog::SearchService.new(search_params)
        entries = search_service.search

        token.touch_last_used!

        response(200, {
          entries: entries.as_json(methods: [:extra_fields_hash]),
          total: entries.count,
          limit: request.params["limit"]&.to_i || 100
        })
      end

      # GET /api/v1/entries/:id
      def handle_entries_show(request, id)
        token = authenticate!(request)
        return token unless token.is_a?(SolidLog::Token)

        entry = SolidLog::Entry.find(id)
        token.touch_last_used!

        response(200, {
          entry: entry.as_json(methods: [:extra_fields_hash])
        })
      rescue ActiveRecord::RecordNotFound
        not_found("Entry not found")
      end

      # GET /api/v1/facets?field=level or GET /api/v1/facets (returns all)
      def handle_facets(request)
        token = authenticate!(request)
        return token unless token.is_a?(SolidLog::Token)

        field = request.params["field"]

        # If no field parameter, return all facets (same as /facets/all)
        if field.blank?
          return handle_facets_all(request)
        end

        limit = request.params["limit"]&.to_i || 100
        facets = SolidLog::Entry.facets_for(field, limit: limit)

        token.touch_last_used!

        response(200, {
          field: field,
          values: facets,
          total: facets.size
        })
      end

      # GET /api/v1/facets/all
      def handle_facets_all(request)
        token = authenticate!(request)
        return token unless token.is_a?(SolidLog::Token)

        facets = {
          level: SolidLog::Entry.facets_for("level"),
          app: SolidLog::Entry.facets_for("app"),
          env: SolidLog::Entry.facets_for("env"),
          controller: SolidLog::Entry.facets_for("controller", limit: 50),
          action: SolidLog::Entry.facets_for("action", limit: 50),
          method: SolidLog::Entry.facets_for("method"),
          status_code: SolidLog::Entry.facets_for("status_code")
        }

        token.touch_last_used!

        response(200, { facets: facets })
      end

      # POST /api/v1/search
      def handle_search(request)
        token = authenticate!(request)
        return token unless token.is_a?(SolidLog::Token)

        # Parse JSON body
        body = request.body.read
        params = body.present? ? JSON.parse(body) : {}

        query = params["q"] || params["query"] || request.params["q"] || request.params["query"]
        if query.blank?
          return bad_request("Query parameter required")
        end

        search_params = {
          query: query,
          limit: params["limit"] || request.params["limit"]
        }.compact

        search_service = SolidLog::SearchService.new(search_params)
        entries = search_service.search

        token.touch_last_used!

        response(200, {
          query: query,
          entries: entries.as_json(methods: [:extra_fields_hash]),
          total: entries.count,
          limit: (params["limit"] || request.params["limit"])&.to_i || 100
        })
      end

      # GET /api/v1/timelines/request/:request_id
      def handle_timeline_request(request, request_id)
        token = authenticate!(request)
        return token unless token.is_a?(SolidLog::Token)

        if request_id.blank?
          return bad_request("Request ID required")
        end

        entries = SolidLog::CorrelationService.request_timeline(request_id)
        stats = SolidLog::CorrelationService.request_stats(request_id)

        token.touch_last_used!

        response(200, {
          request_id: request_id,
          entries: entries.as_json(methods: [:extra_fields_hash]),
          stats: stats
        })
      end

      # GET /api/v1/timelines/job/:job_id
      def handle_timeline_job(request, job_id)
        token = authenticate!(request)
        return token unless token.is_a?(SolidLog::Token)

        if job_id.blank?
          return bad_request("Job ID required")
        end

        entries = SolidLog::CorrelationService.job_timeline(job_id)
        stats = SolidLog::CorrelationService.job_stats(job_id)

        token.touch_last_used!

        response(200, {
          job_id: job_id,
          entries: entries.as_json(methods: [:extra_fields_hash]),
          stats: stats
        })
      end

      # GET /health or /api/v1/health (no authentication)
      def handle_health(request)
        metrics = SolidLog::HealthService.metrics

        status_code = case metrics[:parsing][:health_status]
        when "critical"
          503
        when "warning", "degraded"
          200
        else
          200
        end

        response(status_code, {
          status: metrics[:parsing][:health_status],
          timestamp: Time.current.iso8601,
          metrics: metrics
        })
      end

      # Authentication
      def authenticate!(request)
        header = request.get_header("HTTP_AUTHORIZATION")
        unless header&.match?(/\A(Bearer|bearer) /)
          return unauthorized("Missing or invalid Authorization header")
        end

        token_value = header.sub(/\A(Bearer|bearer) /, "")
        token = SolidLog::Token.authenticate(token_value)

        unless token
          return unauthorized("Invalid token")
        end

        token
      end

      # Parse ingest payload (supports JSON, JSON array, and NDJSON)
      def parse_ingest_payload(request)
        # Check for _json param (Rails-style JSON array parsing)
        return request.params["_json"] if request.params["_json"]

        body = request.body.read
        return [] if body.blank?

        # Check if it's NDJSON (multiple lines) or regular JSON
        if body.include?("\n")
          # NDJSON format
          body.lines.map do |line|
            JSON.parse(line.strip) unless line.strip.empty?
          end.compact
        else
          # Regular JSON (single entry or array)
          JSON.parse(body)
        end
      end

      # Build filter params from request
      def build_filter_params(request)
        params = request.params
        search_params = {}

        # Handle filters hash if present
        if params["filters"].is_a?(Hash)
          filters = params["filters"]
          search_params[:levels] = [filters["level"]].compact if filters["level"].to_s.present?
          search_params[:app] = filters["app"] if filters["app"].to_s.present?
          search_params[:env] = filters["env"] if filters["env"].to_s.present?
          search_params[:controller] = filters["controller"] if filters["controller"].to_s.present?
          search_params[:action] = filters["action"] if filters["action"].to_s.present?
          search_params[:path] = filters["path"] if filters["path"].to_s.present?
          search_params[:method] = filters["method"] if filters["method"].to_s.present?
          search_params[:status_code] = filters["status_code"] if filters["status_code"].to_s.present?
          search_params[:start_time] = filters["start_time"] if filters["start_time"].to_s.present?
          search_params[:end_time] = filters["end_time"] if filters["end_time"].to_s.present?
          search_params[:min_duration] = filters["min_duration"] if filters["min_duration"].to_s.present?
          search_params[:max_duration] = filters["max_duration"] if filters["max_duration"].to_s.present?
        end

        search_params[:query] = params["q"] if params["q"].to_s.present?
        search_params[:limit] = params["limit"] if params["limit"].to_s.present?

        search_params
      end

      # Response helpers
      def response(status, data)
        [status, json_headers, [JSON.generate(data)]]
      end

      def unauthorized(message = "Unauthorized")
        [401, json_headers, [JSON.generate({ error: message })]]
      end

      def bad_request(message)
        [400, json_headers, [JSON.generate({ error: message })]]
      end

      def not_found(message = "Not found")
        [404, json_headers, [JSON.generate({ error: message })]]
      end

      def unprocessable_entity(error, details = nil)
        data = { error: error }
        data[:details] = details if details
        [422, json_headers, [JSON.generate(data)]]
      end

      def internal_error(exception)
        SolidLog::Service.logger.error "SolidLog API Error: #{exception.message}"
        SolidLog::Service.logger.error exception.backtrace.join("\n")

        [500, json_headers, [JSON.generate({
          error: "Internal server error",
          message: exception.message
        })]]
      end

      def json_headers
        { "Content-Type" => "application/json" }
      end
    end
  end
end
