module SolidLog
  class CacheCleanupJob
    def self.perform
      SolidLog.without_logging do
        expired_count = FacetCache.expired.count

        if expired_count > 0
          FacetCache.cleanup_expired!
          SolidLog::Service.logger.info "SolidLog::CacheCleanupJob: Cleaned up #{expired_count} expired cache entries"
        end
      end
    end
  end
end
