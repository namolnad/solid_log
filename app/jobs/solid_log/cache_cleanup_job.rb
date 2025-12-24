module SolidLog
  class CacheCleanupJob < ApplicationJob
    queue_as :default

    def perform
      SolidLog.without_logging do
        expired_count = FacetCache.expired.count

        if expired_count > 0
          FacetCache.cleanup_expired!
          Rails.logger.info "SolidLog::CacheCleanupJob: Cleaned up #{expired_count} expired cache entries"
        end
      end
    end
  end
end
