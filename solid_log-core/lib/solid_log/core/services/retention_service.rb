module SolidLog
  module Core
    class RetentionService
      # Cleanup old entries based on retention policies
      def self.cleanup(retention_days:, error_retention_days:)
        stats = {
          entries_deleted: 0,
          raw_deleted: 0,
          cache_cleared: 0
        }

        # Calculate retention thresholds
        regular_threshold = retention_days.days.ago
        error_threshold = error_retention_days.days.ago

        # Delete old regular logs (not errors)
        stats[:entries_deleted] = Entry
          .where("timestamp < ?", regular_threshold)
          .where.not(level: %w[error fatal])
          .delete_all

        # Delete old error logs
        stats[:entries_deleted] += Entry
          .where("timestamp < ?", error_threshold)
          .where(level: %w[error fatal])
          .delete_all

        # Delete corresponding raw entries (keep unparsed for investigation)
        raw_ids = Entry.pluck(:raw_id).compact
        stats[:raw_deleted] = RawEntry
          .parsed
          .where.not(id: raw_ids)
          .delete_all

        # Clear old cache entries
        stats[:cache_cleared] = FacetCache
          .where("expires_at < ?", Time.current)
          .delete_all

        stats
      end

      # Vacuum database (SQLite only)
      def self.vacuum_database
        return false unless sqlite_database?

        ActiveRecord::Base.connection.execute("VACUUM")
        true
      rescue => e
        Rails.logger.error "RetentionService: VACUUM failed: #{e.message}"
        false
      end

      # Optimize database (SQLite PRAGMA optimize)
      def self.optimize_database
        return false unless sqlite_database?

        ActiveRecord::Base.connection.execute("PRAGMA optimize")
        true
      rescue => e
        Rails.logger.error "RetentionService: PRAGMA optimize failed: #{e.message}"
        false
      end

      private

      def self.sqlite_database?
        ActiveRecord::Base.connection.adapter_name.downcase == "sqlite"
      end
    end
  end
end
