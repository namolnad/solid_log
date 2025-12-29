module SolidLog
  module Api
    module V1
      class FacetsController < Api::BaseController
        # GET /api/v1/facets
        def index
          field = params[:field]

          if field.blank?
            return render json: { error: "Field parameter required" }, status: :bad_request
          end

          # Use Entry model directly for facets
          limit = params[:limit]&.to_i || 100
          facets = SolidLog::Entry.facets_for(field, limit: limit)

          render json: {
            field: field,
            values: facets,
            total: facets.size
          }
        end

        # GET /api/v1/facets/all
        def all
          facets = {
            level: SolidLog::Entry.facets_for('level'),
            app: SolidLog::Entry.facets_for('app'),
            env: SolidLog::Entry.facets_for('env'),
            controller: SolidLog::Entry.facets_for('controller', limit: 50),
            action: SolidLog::Entry.facets_for('action', limit: 50),
            method: SolidLog::Entry.facets_for('method'),
            status_code: SolidLog::Entry.facets_for('status_code')
          }

          render json: { facets: facets }
        end
      end
    end
  end
end
