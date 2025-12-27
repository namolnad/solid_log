module SolidLog
  class StreamsController < ApplicationController
    def index
      @search_service = SearchService.new(params[:filters] || {})

      @entries = SolidLog.without_logging do
        @search_service.search
      end

      @available_filters = SolidLog.without_logging do
        @search_service.available_facets
      end

      @current_filters = current_filters

      # Generate timeline data for visualization
      @timeline_data = SolidLog.without_logging do
        generate_timeline_data
      end

      respond_to do |format|
        format.html
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("log-stream-content", partial: "log_stream_content", locals: { entries: @entries, query: @current_filters[:query] }),
            turbo_stream.replace("timeline-container", partial: "timeline", locals: { timeline_data: @timeline_data, current_filters: @current_filters }),
            turbo_stream.append("toast-container", partial: "toast_message", locals: { message: "Jumped to live", type: "success" })
          ]
        end
      end
    end

    private

    def current_filters
      filter_params = params.fetch(:filters, {})
      filters = {
        query: filter_params[:query],
        levels: Array(filter_params[:levels]).reject(&:blank?),
        app: Array(filter_params[:app]).flatten.reject(&:blank?),
        env: Array(filter_params[:env]).flatten.reject(&:blank?),
        controller: Array(filter_params[:controller]).flatten.reject(&:blank?),
        action: Array(filter_params[:action]).flatten.reject(&:blank?),
        path: Array(filter_params[:path]).flatten.reject(&:blank?),
        method: Array(filter_params[:method]).flatten.reject(&:blank?),
        status_code: Array(filter_params[:status_code]).flatten.reject(&:blank?),
        min_duration: filter_params[:min_duration],
        max_duration: filter_params[:max_duration],
        start_time: filter_params[:start_time],
        end_time: filter_params[:end_time],
        request_id: filter_params[:request_id],
        job_id: filter_params[:job_id]
      }

      # Add promoted field filters based on their filter type
      Field.promoted.each do |field|
        next unless Entry.column_names.include?(field.name)

        case field.filter_type
        when "multiselect"
          filters[field.name.to_sym] = Array(filter_params[field.name.to_sym]).flatten.reject(&:blank?)
        when "tokens"
          # Keep as string for parsing in SearchService
          filters[field.name.to_sym] = filter_params[field.name.to_sym]
        when "range"
          filters["min_#{field.name}".to_sym] = filter_params["min_#{field.name}".to_sym]
          filters["max_#{field.name}".to_sym] = filter_params["max_#{field.name}".to_sym]
        else
          filters[field.name.to_sym] = filter_params[field.name.to_sym]
        end
      end

      filters
    end

    def generate_timeline_data
      # Get the time range for the currently displayed entries
      return { buckets: [], start_time: nil, end_time: nil } if @entries.empty?

      # Determine time range: use filter times if present, otherwise use entry times
      # Note: entries are in ascending order (oldest first, newest last)
      start_time = if @current_filters[:start_time].present?
        Time.zone.parse(@current_filters[:start_time])
      else
        @entries.first.timestamp  # oldest entry
      end

      end_time = if @current_filters[:end_time].present?
        Time.zone.parse(@current_filters[:end_time])
      else
        @entries.last.timestamp  # newest entry
      end

      # Calculate appropriate bucket size based on time range
      time_range = end_time - start_time
      bucket_count = 50 # Number of buckets to display

      bucket_size = if time_range < 1.hour
        1.minute
      elsif time_range < 1.day
        5.minutes
      elsif time_range < 1.week
        1.hour
      else
        6.hours
      end

      # Generate buckets
      buckets = []
      current_time = start_time
      bucket_count.times do
        bucket_end = current_time + bucket_size
        # break if current_time >= end_time

        # Count entries in this bucket (from all entries matching current filters, not just displayed)
        count = Entry.where(timestamp: current_time...bucket_end)
          .yield_self { |scope| apply_current_filters_to_scope(scope) }
          .count

        buckets << {
          start_time: current_time,
          end_time: bucket_end,
          count: count
        }

        current_time = bucket_end
      end

      {
        buckets: buckets,
        start_time: start_time,
        end_time: end_time,
        bucket_size: bucket_size
      }
    end

    def apply_current_filters_to_scope(scope)
      # Apply the same filters as SearchService to get accurate counts
      scope = scope.where(level: @current_filters[:levels]) if @current_filters[:levels].any?
      scope = scope.by_app(@current_filters[:app]) if @current_filters[:app].any?
      scope = scope.by_env(@current_filters[:env]) if @current_filters[:env].any?
      scope = scope.by_controller(@current_filters[:controller]) if @current_filters[:controller].any?
      scope = scope.by_action(@current_filters[:action]) if @current_filters[:action].any?
      scope = scope.by_path(@current_filters[:path]) if @current_filters[:path].any?
      scope = scope.by_method(@current_filters[:method]) if @current_filters[:method].any?
      scope = scope.by_status_code(@current_filters[:status_code]) if @current_filters[:status_code].any?
      scope = scope.by_request_id(@current_filters[:request_id]) if @current_filters[:request_id].present?
      scope = scope.by_job_id(@current_filters[:job_id]) if @current_filters[:job_id].present?
      scope
    end
  end
end
