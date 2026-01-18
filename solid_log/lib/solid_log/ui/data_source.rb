require_relative "api_client"

module SolidLog
  module UI
    class DataSource
      # Query entries with filters
      def entries(filters = {})
        if direct_db_mode?
          query_direct_db(filters)
        else
          query_http_api(filters)
        end
      end

      # Get single entry by ID
      def entry(id)
        if direct_db_mode?
          SolidLog::Entry.find(id)
        else
          result = api_client.entry(id)
          OpenStruct.new(result["entry"])
        end
      end

      # Full-text search
      def search(query, filters = {})
        if direct_db_mode?
          entries = SolidLog::SearchService.search(query)
          apply_filters(entries, filters)
        else
          result = api_client.search(query, filters)
          parse_entries_response(result)
        end
      end

      # Get facets for a field
      def facets(field)
        if direct_db_mode?
          SolidLog::SearchService.facets_for(field)
        else
          result = api_client.facets(field)
          result["values"]
        end
      end

      # Get all facets
      def all_facets
        if direct_db_mode?
          {
            level: SolidLog::SearchService.facets_for("level"),
            app: SolidLog::SearchService.facets_for("app"),
            env: SolidLog::SearchService.facets_for("env"),
            controller: SolidLog::SearchService.facets_for("controller"),
            action: SolidLog::SearchService.facets_for("action"),
            method: SolidLog::SearchService.facets_for("method"),
            status_code: SolidLog::SearchService.facets_for("status_code")
          }
        else
          result = api_client.all_facets
          result["facets"]
        end
      end

      # Get request timeline
      def request_timeline(request_id)
        if direct_db_mode?
          {
            request_id: request_id,
            entries: SolidLog::CorrelationService.request_timeline(request_id),
            stats: SolidLog::CorrelationService.request_stats(request_id)
          }
        else
          api_client.request_timeline(request_id)
        end
      end

      # Get job timeline
      def job_timeline(job_id)
        if direct_db_mode?
          {
            job_id: job_id,
            entries: SolidLog::CorrelationService.job_timeline(job_id),
            stats: SolidLog::CorrelationService.job_stats(job_id)
          }
        else
          api_client.job_timeline(job_id)
        end
      end

      # Get health metrics
      def health
        if direct_db_mode?
          SolidLog::HealthService.metrics
        else
          api_client.health["metrics"]
        end
      end

      private

      def direct_db_mode?
        SolidLog::UI.configuration.direct_db_mode?
      end

      def http_api_mode?
        SolidLog::UI.configuration.http_api_mode?
      end

      def api_client
        @api_client ||= ApiClient.new
      end

      def query_direct_db(filters)
        SolidLog::SearchService.query(filters).recent.limit(per_page)
      end

      def query_http_api(filters)
        result = api_client.entries(filters.merge(limit: per_page))
        parse_entries_response(result)
      end

      def apply_filters(scope, filters)
        scope = scope.by_level(filters[:level]) if filters[:level].present?
        scope = scope.by_app(filters[:app]) if filters[:app].present?
        scope = scope.by_env(filters[:env]) if filters[:env].present?
        scope = scope.by_controller(filters[:controller]) if filters[:controller].present?
        scope = scope.by_action(filters[:action]) if filters[:action].present?
        scope = scope.by_path(filters[:path]) if filters[:path].present?
        scope = scope.by_method(filters[:method]) if filters[:method].present?
        scope = scope.by_status_code(filters[:status_code]) if filters[:status_code].present?

        scope.recent.limit(per_page)
      end

      def parse_entries_response(result)
        # Convert API response to array of OpenStruct objects
        # This makes them compatible with views that expect ActiveRecord objects
        (result["entries"] || []).map { |entry| OpenStruct.new(entry) }
      end

      def per_page
        SolidLog::UI.configuration.per_page
      end
    end
  end
end
