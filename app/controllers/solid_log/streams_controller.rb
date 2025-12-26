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
  end
end
