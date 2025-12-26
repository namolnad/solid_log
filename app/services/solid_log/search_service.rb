module SolidLog
  class SearchService
    def initialize(params = {})
      @params = params
      @cache_enabled = SolidLog.configuration.facet_cache_ttl.present?
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
        controllers: Entry.facets_for("controller"),
        actions: Entry.facets_for("action"),
        paths: Entry.facets_for("path"),
        methods: Entry.facets_for("method"),
        status_codes: Entry.facets_for("status_code")
      }

      # Add promoted fields dynamically
      facets.merge!(promoted_field_facets)

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
      # scope = apply_controller_filter(scope)
      scope = apply_action_filter(scope)
      scope = apply_path_filter(scope)
      scope = apply_method_filter(scope)
      scope = apply_status_code_filter(scope)
      scope = apply_duration_filter(scope)
      scope = apply_time_range_filter(scope)
      scope = apply_correlation_filters(scope)
      scope = apply_promoted_field_filters(scope)
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

    def apply_controller_filter(scope)
      return scope if @params[:controller].blank?
      scope.by_controller(@params[:controller])
    end

    def apply_action_filter(scope)
      return scope if @params[:action].blank?
      scope.by_action(@params[:action])
    end

    def apply_path_filter(scope)
      return scope if @params[:path].blank?
      scope.by_path(@params[:path])
    end

    def apply_method_filter(scope)
      return scope if @params[:method].blank?
      scope.by_method(@params[:method])
    end

    def apply_status_code_filter(scope)
      return scope if @params[:status_code].blank?
      scope.by_status_code(@params[:status_code])
    end

    def apply_duration_filter(scope)
      min_duration = @params[:min_duration].presence
      max_duration = @params[:max_duration].presence
      return scope if min_duration.blank? && max_duration.blank?

      scope.by_duration_range(min_duration, max_duration)
    end

    def apply_promoted_field_filters(scope)
      # Apply filters for any promoted fields that have columns
      Field.promoted.each do |field|
        next unless Entry.column_names.include?(field.name)

        # Handle different filter types
        case field.filter_type
        when "multiselect"
          values = Array(@params[field.name.to_sym]).reject(&:blank?)
          next if values.empty?
          scope = scope.where(field.name => values)
        when "tokens"
          values = parse_token_values(@params[field.name.to_sym])
          next if values.empty?
          scope = scope.where(field.name => values)
        when "range"
          min_value = @params["min_#{field.name}".to_sym].presence
          max_value = @params["max_#{field.name}".to_sym].presence
          next if min_value.blank? && max_value.blank?
          scope = scope.where("#{field.name} >= ?", min_value) if min_value.present?
          scope = scope.where("#{field.name} <= ?", max_value) if max_value.present?
        when "exact", "contains"
          param_value = @params[field.name.to_sym]
          next if param_value.blank?
          if field.filter_type == "contains"
            scope = scope.where("#{field.name} LIKE ?", "%#{param_value}%")
          else
            scope = scope.where(field.name => param_value)
          end
        end
      end
      scope
    end

    def parse_datetime(datetime_str)
      return nil if datetime_str.blank?

      Time.zone.parse(datetime_str)
    rescue ArgumentError
      nil
    end

    def parse_token_values(input)
      return [] if input.blank?

      # Split by comma, semicolon, or newline and clean up
      input.to_s.split(/[,;\n]/).map(&:strip).reject(&:blank?)
    end

    def limit
      limit = @params[:limit].to_i
      limit > 0 ? [ limit, 1000 ].min : 200
    end

    def cache_enabled?
      @cache_enabled
    end

    def promoted_field_facets
      promoted_facets = {}

      # Get all promoted fields that have actual database columns
      Field.promoted.each do |field|
        # Skip token fields - we don't fetch facets for high-cardinality fields
        next if field.filter_type == "tokens"

        # Check if the column exists on the entries table
        if Entry.column_names.include?(field.name)
          # Get distinct values for this field
          values = Entry.facets_for(field.name)
          promoted_facets[field.name.to_sym] = values if values.any?
        end
      end

      promoted_facets
    end

    def cached_facets
      FacetCache.fetch("facets:all", ttl: cache_ttl) do
        facets = {
          levels: Entry.facets_for("level"),
          apps: Entry.facets_for("app"),
          envs: Entry.facets_for("env"),
          controllers: Entry.facets_for("controller"),
          actions: Entry.facets_for("action"),
          paths: Entry.facets_for("path"),
          methods: Entry.facets_for("method"),
          status_codes: Entry.facets_for("status_code")
        }
        facets.merge!(promoted_field_facets)
        facets
      end
    end

    def cache_facets(facets)
      FacetCache.store("facets:all", facets, ttl: cache_ttl)
    end

    def cache_ttl
      SolidLog.configuration.facet_cache_ttl
    end
  end
end
