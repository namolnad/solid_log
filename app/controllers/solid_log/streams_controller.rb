module SolidLog
  class StreamsController < ApplicationController
    def index
      @search_service = SearchService.new(params)

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
      filters = {
        query: params[:query],
        levels: Array(params[:levels]).reject(&:blank?),
        app: Array(params[:app]).reject(&:blank?),
        env: Array(params[:env]).reject(&:blank?),
        controller: Array(params[:controller]).reject(&:blank?),
        action: Array(params[:action]).reject(&:blank?),
        path: Array(params[:path]).reject(&:blank?),
        method: Array(params[:method]).reject(&:blank?),
        status_code: Array(params[:status_code]).reject(&:blank?),
        min_duration: params[:min_duration],
        max_duration: params[:max_duration],
        start_time: params[:start_time],
        end_time: params[:end_time],
        request_id: params[:request_id],
        job_id: params[:job_id]
      }

      # Add promoted field filters based on their filter type
      Field.promoted.each do |field|
        next unless Entry.column_names.include?(field.name)

        case field.filter_type
        when "multiselect"
          filters[field.name.to_sym] = Array(params[field.name.to_sym]).reject(&:blank?)
        when "tokens"
          # Keep as string for parsing in SearchService
          filters[field.name.to_sym] = params[field.name.to_sym]
        when "range"
          filters["min_#{field.name}".to_sym] = params["min_#{field.name}".to_sym]
          filters["max_#{field.name}".to_sym] = params["max_#{field.name}".to_sym]
        else
          filters[field.name.to_sym] = params[field.name.to_sym]
        end
      end

      filters
    end
  end
end
