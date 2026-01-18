module SolidLog
  module UI
    class EntriesController < BaseController
      def index
        # Redirect to streams for better UX
        redirect_to streams_path
      end

      def show
        @entry = SolidLog.without_logging do
          Entry.find(params[:id])
        end

        @correlated_entries = find_correlated_entries if @entry.correlated?
      end

      private

      def find_correlated_entries
        SolidLog.without_logging do
          scope = Entry.where.not(id: @entry.id)

          if @entry.request_id.present?
            scope = scope.by_request_id(@entry.request_id)
          elsif @entry.job_id.present?
            scope = scope.by_job_id(@entry.job_id)
          end

          scope.recent.limit(50)
        end
      end
    end
  end
end
