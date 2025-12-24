module SolidLog
  class HealthService
    def self.metrics
      SolidLog.without_logging do
        {
          ingestion: ingestion_metrics,
          parsing: parsing_metrics,
          storage: storage_metrics,
          performance: performance_metrics
        }
      end
    end

    def self.ingestion_metrics
      {
        total_raw: RawEntry.count,
        today_raw: RawEntry.where("received_at >= ?", Time.current.beginning_of_day).count,
        last_hour_raw: RawEntry.where("received_at >= ?", 1.hour.ago).count,
        last_ingestion: RawEntry.order(received_at: :desc).first&.received_at
      }
    end

    def self.parsing_metrics
      unparsed = RawEntry.unparsed.count
      total_raw = RawEntry.count

      {
        unparsed_count: unparsed,
        parse_backlog_percentage: total_raw.zero? ? 0 : (unparsed.to_f / total_raw * 100).round(2),
        stale_unparsed: RawEntry.stale_unparsed(1.hour.ago).count,
        last_parse: RawEntry.parsed.order(parsed_at: :desc).first&.parsed_at,
        health_status: parse_health_status(unparsed)
      }
    end

    def self.storage_metrics
      {
        total_entries: Entry.count,
        total_fields: Field.count,
        promoted_fields: Field.promoted.count,
        hot_fields_count: Field.hot_fields(1000).count,
        oldest_entry: Entry.order(:created_at).first&.created_at,
        newest_entry: Entry.order(created_at: :desc).first&.created_at,
        database_size: calculate_database_size
      }
    end

    def self.performance_metrics
      {
        cache_entries: FacetCache.count,
        expired_cache: FacetCache.expired.count,
        error_rate: calculate_error_rate,
        avg_duration: calculate_avg_duration
      }
    end

    def self.parse_health_status(unparsed_count)
      if unparsed_count == 0
        :healthy
      elsif unparsed_count < 100
        :ok
      elsif unparsed_count < 1000
        :warning
      else
        :critical
      end
    end

    def self.calculate_database_size
      db_path = ActiveRecord::Base.connection_db_config.database
      return "Unknown" unless File.exist?(db_path)

      size_bytes = File.size(db_path)
      format_bytes(size_bytes)
    end

    def self.format_bytes(bytes)
      units = %w[B KB MB GB TB]
      size = bytes.to_f
      unit_index = 0

      while size >= 1024 && unit_index < units.length - 1
        size /= 1024
        unit_index += 1
      end

      "#{size.round(2)} #{units[unit_index]}"
    end

    def self.calculate_error_rate
      total = Entry.where("created_at >= ?", 1.hour.ago).count
      errors = Entry.where("created_at >= ?", 1.hour.ago)
                   .where(level: %w[error fatal]).count

      return 0 if total.zero?

      (errors.to_f / total * 100).round(2)
    end

    def self.calculate_avg_duration
      avg = Entry.where("created_at >= ?", 1.hour.ago)
                .where.not(duration: nil)
                .average(:duration)

      avg&.round(2) || 0
    end
  end
end
