# frozen_string_literal: true

module SolidLog
  module Core
    module Jobs
      # Conditionally inherit from ActiveJob if available
      if defined?(ActiveJob::Base)
        BaseJob = ActiveJob::Base
      else
        # Plain Ruby class when ActiveJob not available
        BaseJob = Class.new do
          def self.queue_as(*); end  # No-op when not using ActiveJob
          def self.perform_later(*args, **kwargs)
            new.perform(*args, **kwargs)
          end
          def self.perform_now(*args, **kwargs)
            new.perform(*args, **kwargs)
          end
        end
      end

      class CacheCleanupJob < BaseJob
        queue_as :default

        def perform
          SolidLog.without_logging do
            expired_count = SolidLog::FacetCache.expired.count

            if expired_count > 0
              SolidLog::FacetCache.cleanup_expired!
              logger.info "SolidLog::CacheCleanupJob: Cleaned up #{expired_count} expired cache entries"
            end
          end
        rescue => e
          logger.error "SolidLog::CacheCleanupJob failed: #{e.message}"
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
