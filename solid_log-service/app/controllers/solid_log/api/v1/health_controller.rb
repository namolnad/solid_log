module SolidLog
  module Api
    module V1
      class HealthController < Api::BaseController
        skip_before_action :authenticate_token!, only: [:show]

        # GET /api/v1/health
        def show
          metrics = SolidLog::HealthService.metrics

          status = case metrics[:parsing][:health_status]
          when "critical"
                    :service_unavailable
          when "warning", "degraded"
                    :ok  # Still functional
          else
                    :ok
          end

          render json: {
            status: metrics[:parsing][:health_status],
            timestamp: Time.current.iso8601,
            metrics: metrics
          }, status: status
        end
      end
    end
  end
end
