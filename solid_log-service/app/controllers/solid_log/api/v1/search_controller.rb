module SolidLog
  module Api
    module V1
      class SearchController < Api::BaseController
        # POST /api/v1/search
        def create
          query = params[:q] || params[:query]

          if query.blank?
            return render json: { error: "Query parameter required" }, status: :bad_request
          end

          search_params = {
            query: query,
            limit: params[:limit]
          }.compact

          search_service = SolidLog::SearchService.new(search_params)
          entries = search_service.search

          render json: {
            query: query,
            entries: entries.as_json(methods: [:extra_fields_hash]),
            total: entries.count,
            limit: params[:limit]&.to_i || 100
          }
        end
      end
    end
  end
end
