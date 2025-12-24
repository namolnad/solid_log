module SolidLog
  class SearchService
    def initialize(params = {})
      @params = params
      @cache_enabled = true
    end

    def search
      scope = Entry.all

      # Apply search query
      scope = apply_search(scope)

      # Apply filters
      scope = apply_filters(scope)

      # Return scoped results
      scope.recent.limit(limit)
    end

    def available_facets
      return cached_facets if cache_enabled?

      facets = {
        levels: Entry.facets_for("level"),
        apps: Entry.facets_for("app"),
        envs: Entry.facets_for("env"),
        controllers: Entry.facets_for("controller").take(50),
        methods: Entry.facets_for("method")
      }

      cache_facets(facets) if cache_enabled?
      facets
    end

    private

    def apply_search(scope)
      return scope if @params[:query].blank?

      Entry.search_fts(@params[:query])
    end

    def apply_filters(scope)
      scope = apply_level_filter(scope)
      scope = apply_app_filter(scope)
      scope = apply_env_filter(scope)
      scope = apply_time_range_filter(scope)
      scope = apply_correlation_filters(scope)
      scope
    end

    def apply_level_filter(scope)
      levels = Array(@params[:levels]).reject(&:blank?)
      return scope if levels.empty?

      scope.where(level: levels)
    end

    def apply_app_filter(scope)
      return scope if @params[:app].blank?

      scope.by_app(@params[:app])
    end

    def apply_env_filter(scope)
      return scope if @params[:env].blank?

      scope.by_env(@params[:env])
    end

    def apply_time_range_filter(scope)
      start_time = parse_datetime(@params[:start_time])
      end_time = parse_datetime(@params[:end_time])

      scope.by_time_range(start_time, end_time)
    end

    def apply_correlation_filters(scope)
      scope = scope.by_request_id(@params[:request_id]) if @params[:request_id].present?
      scope = scope.by_job_id(@params[:job_id]) if @params[:job_id].present?
      scope
    end

    def parse_datetime(datetime_str)
      return nil if datetime_str.blank?

      Time.zone.parse(datetime_str)
    rescue ArgumentError
      nil
    end

    def limit
      limit = @params[:limit].to_i
      limit > 0 ? [ limit, 1000 ].min : 200
    end

    def cache_enabled?
      @cache_enabled
    end

    def cached_facets
      FacetCache.fetch("facets:all", ttl: 5.minutes) do
        {
          levels: Entry.facets_for("level"),
          apps: Entry.facets_for("app"),
          envs: Entry.facets_for("env"),
          controllers: Entry.facets_for("controller").take(50),
          methods: Entry.facets_for("method")
        }
      end
    end

    def cache_facets(facets)
      FacetCache.store("facets:all", facets, ttl: 5.minutes)
    end
  end
end
