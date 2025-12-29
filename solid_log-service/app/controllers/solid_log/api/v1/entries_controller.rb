module SolidLog
  module Api
    module V1
      class EntriesController < Api::BaseController
        # GET /api/v1/entries
        def index
          search_service = SolidLog::SearchService.new(filter_params)
          entries = search_service.search

          render json: {
            entries: entries.as_json(methods: [:extra_fields_hash]),
            total: entries.count,
            limit: params[:limit]&.to_i || 100
          }
        end

        # GET /api/v1/entries/:id
        def show
          entry = Entry.find(params[:id])

          render json: {
            entry: entry.as_json(methods: [:extra_fields_hash])
          }
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Entry not found" }, status: :not_found
        end

        private

        def filter_params
          # Extract filters from params[:filters] to avoid Rails routing params collision
          search_params = {}
          filters = params[:filters] || {}

          search_params[:levels] = [filters[:level]].compact if filters[:level].present?
          search_params[:app] = filters[:app] if filters[:app].present?
          search_params[:env] = filters[:env] if filters[:env].present?
          search_params[:controller] = filters[:controller] if filters[:controller].present?
          search_params[:action] = filters[:action] if filters[:action].present?
          search_params[:path] = filters[:path] if filters[:path].present?
          search_params[:method] = filters[:method] if filters[:method].present?
          search_params[:status_code] = filters[:status_code] if filters[:status_code].present?
          search_params[:start_time] = filters[:start_time] if filters[:start_time].present?
          search_params[:end_time] = filters[:end_time] if filters[:end_time].present?
          search_params[:min_duration] = filters[:min_duration] if filters[:min_duration].present?
          search_params[:max_duration] = filters[:max_duration] if filters[:max_duration].present?
          search_params[:query] = params[:q] if params[:q].present?
          search_params[:limit] = params[:limit] if params[:limit].present?

          search_params
        end
      end
    end
  end
end
