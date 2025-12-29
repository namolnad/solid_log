module SolidLog
  module Core
    class HealthService
      # Get comprehensive health metrics
      def self.metrics
        {
          ingestion: ingestion_metrics,
          parsing: parsing_metrics,
          storage: storage_metrics,
          performance: performance_metrics
        }
      end

      # Ingestion metrics
      def self.ingestion_metrics
        today_start = Time.current.beginning_of_day
        hour_ago = 1.hour.ago

        {
          total_raw: RawEntry.count,
          today_raw: RawEntry.where("received_at >= ?", today_start).count,
          last_hour_raw: RawEntry.where("received_at >= ?", hour_ago).count,
          last_ingestion: RawEntry.order(received_at: :desc).first&.received_at
        }
      end

      # Parsing metrics
      def self.parsing_metrics
        unparsed_count = RawEntry.unparsed.count
        total_raw = RawEntry.count
        stale_threshold = 1.hour.ago

        backlog_percentage = total_raw > 0 ? (unparsed_count.to_f / total_raw * 100).round(2) : 0
        stale_unparsed = RawEntry.unparsed.where("received_at < ?", stale_threshold).count

        health_status = case
        when backlog_percentage > 50
                         "critical"
        when backlog_percentage > 20
                         "warning"
        when stale_unparsed > 100
                         "degraded"
        else
                         "healthy"
        end

        {
          unparsed_count: unparsed_count,
          parse_backlog_percentage: backlog_percentage,
          stale_unparsed: stale_unparsed,
          health_status: health_status
        }
      end

      # Storage metrics
      def self.storage_metrics
        promoted_fields = Field.promoted.count
        hot_fields = Field.hot_fields(1000).count

        {
          total_entries: Entry.count,
          total_fields: Field.count,
          promoted_fields: promoted_fields,
          hot_fields_count: hot_fields,
          database_size: database_size
        }
      end

      # Performance metrics
      def self.performance_metrics
        hour_ago = 1.hour.ago
        hour_entries = Entry.where("timestamp >= ?", hour_ago)

        error_count = hour_entries.errors.count
        total_count = hour_entries.count
        error_rate = total_count > 0 ? (error_count.to_f / total_count * 100).round(2) : 0

        avg_duration = hour_entries
          .where.not(duration: nil)
          .average(:duration)
          &.round(2) || 0

        {
          cache_entries: FacetCache.count,
          expired_cache: FacetCache.where("expires_at < ?", Time.current).count,
          error_rate: error_rate,
          avg_duration: avg_duration
        }
      end

      # Get database size (platform-specific)
      def self.database_size
        adapter_name = ActiveRecord::Base.connection.adapter_name.downcase

        case adapter_name
        when "sqlite"
          sqlite_database_size
        when "postgresql"
          postgresql_database_size
        when "mysql"
          mysql_database_size
        else
          "Unknown"
        end
      rescue => e
        Rails.logger.error "HealthService: Error getting database size: #{e.message}"
        "Error"
      end

      private

      def self.sqlite_database_size
        db_path = ActiveRecord::Base.connection_db_config.database
        return "Unknown" unless File.exist?(db_path)

        size_bytes = File.size(db_path)
        format_bytes(size_bytes)
      end

      def self.postgresql_database_size
        db_name = ActiveRecord::Base.connection_db_config.database
        result = ActiveRecord::Base.connection.execute(
          "SELECT pg_database_size('#{db_name}')"
        )
        size_bytes = result.first["pg_database_size"].to_i
        format_bytes(size_bytes)
      end

      def self.mysql_database_size
        db_name = ActiveRecord::Base.connection_db_config.database
        result = ActiveRecord::Base.connection.execute(
          "SELECT SUM(data_length + index_length) as size
           FROM information_schema.TABLES
           WHERE table_schema = '#{db_name}'"
        )
        size_bytes = result.first[0].to_i
        format_bytes(size_bytes)
      end

      def self.format_bytes(bytes)
        return "0 B" if bytes == 0

        units = %w[B KB MB GB TB]
        exp = (Math.log(bytes) / Math.log(1024)).to_i
        exp = [exp, units.size - 1].min

        "%.2f %s" % [bytes.to_f / (1024 ** exp), units[exp]]
      end
    end
  end
end
