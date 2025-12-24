module SolidLog
  class RetentionJob < ApplicationJob
    queue_as :default

    def perform(retention_days: 30, error_retention_days: 90, vacuum: false)
      SolidLog.without_logging do
        Rails.logger.info "SolidLog::RetentionJob: Starting cleanup (retention: #{retention_days} days, errors: #{error_retention_days} days)"

        stats = RetentionService.cleanup(
          retention_days: retention_days,
          error_retention_days: error_retention_days
        )

        Rails.logger.info "SolidLog::RetentionJob: Deleted #{stats[:entries_deleted]} entries, #{stats[:raw_deleted]} raw entries, cleared #{stats[:cache_cleared]} cache entries"

        if vacuum
          Rails.logger.info "SolidLog::RetentionJob: Running VACUUM..."
          RetentionService.vacuum_database
          Rails.logger.info "SolidLog::RetentionJob: VACUUM complete"
        end
      end
    end
  end
end
