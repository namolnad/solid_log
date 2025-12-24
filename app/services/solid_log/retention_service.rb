module SolidLog
  class RetentionService
    DEFAULT_RETENTION_DAYS = 30
    DEFAULT_ERROR_RETENTION_DAYS = 90
    BATCH_SIZE = 1000

    def self.cleanup(retention_days: DEFAULT_RETENTION_DAYS, error_retention_days: DEFAULT_ERROR_RETENTION_DAYS)
      SolidLog.without_logging do
        stats = {
          entries_deleted: 0,
          raw_deleted: 0,
          cache_cleared: 0
        }

        # Delete old entries (errors have longer retention)
        stats[:entries_deleted] += delete_old_entries(retention_days, error_retention_days)

        # Delete old parsed raw entries
        stats[:raw_deleted] += delete_old_raw_entries(retention_days)

        # Clear expired cache
        stats[:cache_cleared] = clear_expired_cache

        stats
      end
    end

    def self.delete_old_entries(retention_days, error_retention_days)
      # Keep errors longer
      error_threshold = error_retention_days.days.ago
      regular_threshold = retention_days.days.ago

      deleted_count = 0

      # Delete regular logs older than retention_days
      loop do
        batch_count = Entry.where("created_at < ?", regular_threshold)
                          .where.not(level: %w[error fatal])
                          .limit(BATCH_SIZE)
                          .delete_all

        deleted_count += batch_count
        break if batch_count < BATCH_SIZE
      end

      # Delete error logs older than error_retention_days
      loop do
        batch_count = Entry.where("created_at < ?", error_threshold)
                          .where(level: %w[error fatal])
                          .limit(BATCH_SIZE)
                          .delete_all

        deleted_count += batch_count
        break if batch_count < BATCH_SIZE
      end

      deleted_count
    end

    def self.delete_old_raw_entries(retention_days)
      # Only delete parsed raw entries older than retention
      threshold = retention_days.days.ago
      deleted_count = 0

      loop do
        batch_count = RawEntry.parsed
                              .where("parsed_at < ?", threshold)
                              .limit(BATCH_SIZE)
                              .delete_all

        deleted_count += batch_count
        break if batch_count < BATCH_SIZE
      end

      deleted_count
    end

    def self.clear_expired_cache
      FacetCache.expired.delete_all
    end

    def self.vacuum_database
      # Run VACUUM on SQLite to reclaim space
      ActiveRecord::Base.connection.execute("VACUUM")
      true
    rescue StandardError => e
      Rails.logger.error "SolidLog: VACUUM failed: #{e.message}"
      false
    end

    def self.optimize_database
      # Optimize SQLite database
      ActiveRecord::Base.connection.execute("PRAGMA optimize")
      true
    rescue StandardError => e
      Rails.logger.error "SolidLog: Optimize failed: #{e.message}"
      false
    end
  end
end
