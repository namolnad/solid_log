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
      {
        query: params[:query],
        levels: Array(params[:levels]).reject(&:blank?),
        app: params[:app],
        env: params[:env],
        start_time: params[:start_time],
        end_time: params[:end_time],
        request_id: params[:request_id],
        job_id: params[:job_id]
      }
    end
  end
end
