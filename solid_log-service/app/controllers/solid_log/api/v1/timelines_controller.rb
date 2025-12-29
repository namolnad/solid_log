module SolidLog
  module Api
    module V1
      class TimelinesController < Api::BaseController
        # GET /api/v1/timelines/request/:request_id
        def show_request
          request_id = params[:request_id]

          if request_id.blank?
            return render json: { error: "Request ID required" }, status: :bad_request
          end

          entries = SolidLog::CorrelationService.request_timeline(request_id)
          stats = SolidLog::CorrelationService.request_stats(request_id)

          render json: {
            request_id: request_id,
            entries: entries.as_json(methods: [:extra_fields_hash]),
            stats: stats
          }
        end

        # GET /api/v1/timelines/job/:job_id
        def show_job
          job_id = params[:job_id]

          if job_id.blank?
            return render json: { error: "Job ID required" }, status: :bad_request
          end

          entries = SolidLog::CorrelationService.job_timeline(job_id)
          stats = SolidLog::CorrelationService.job_stats(job_id)

          render json: {
            job_id: job_id,
            entries: entries.as_json(methods: [:extra_fields_hash]),
            stats: stats
          }
        end
      end
    end
  end
end
