# frozen_string_literal: true

module SolidLog
  module Core
    module Jobs
      class RetentionJob < BaseJob
        queue_as :default

        def perform(retention_days: nil, error_retention_days: nil, max_entries: nil, vacuum: false)
          retention_days ||= SolidLog.configuration.retention_days
          error_retention_days ||= SolidLog.configuration.error_retention_days
          max_entries ||= SolidLog.configuration.max_entries

          SolidLog.without_logging do
            logger.info "SolidLog::RetentionJob: Starting cleanup (retention: #{retention_days} days, errors: #{error_retention_days} days, max_entries: #{max_entries || 'unlimited'})"

            stats = SolidLog::Core::RetentionService.cleanup(
              retention_days: retention_days,
              error_retention_days: error_retention_days,
              max_entries: max_entries
            )

            logger.info "SolidLog::RetentionJob: Deleted #{stats[:entries_deleted]} entries, #{stats[:raw_deleted]} raw entries, cleared #{stats[:cache_cleared]} cache entries"

            if vacuum
              logger.info "SolidLog::RetentionJob: Running VACUUM..."
              SolidLog::Core::RetentionService.vacuum_database
              logger.info "SolidLog::RetentionJob: VACUUM complete"
            end
          end

          stats
        rescue => e
          logger.error "SolidLog::RetentionJob failed: #{e.message}"
          # Re-raise for ActiveJob retry if available, otherwise just log
          raise if defined?(ActiveJob::Base)
        end

        private

        def logger
          defined?(SolidLog) && SolidLog.respond_to?(:logger) ? SolidLog.logger : Logger.new(STDOUT)
        end
      end
    end
  end
end
