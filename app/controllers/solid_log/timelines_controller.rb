module SolidLog
  class TimelinesController < ApplicationController
    def request
      @request_id = params[:request_id]

      @entries = SolidLog.without_logging do
        Entry.by_request_id(@request_id).recent
      end

      if @entries.empty?
        redirect_to streams_path, alert: "No entries found for request ID: #{@request_id}"
      end
    end

    def job
      @job_id = params[:job_id]

      @entries = SolidLog.without_logging do
        Entry.by_job_id(@job_id).recent
      end

      if @entries.empty?
        redirect_to streams_path, alert: "No entries found for job ID: #{@job_id}"
      end
    end
  end
end
