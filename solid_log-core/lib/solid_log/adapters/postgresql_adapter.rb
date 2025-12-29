module SolidLog
  module Adapters
    class PostgresqlAdapter < BaseAdapter
      def search(query, base_scope = Entry)
        sanitized_query = Entry.sanitize_sql_like(query)
        table_name = Entry.table_name

        # Build LIKE query for partial matching
        like_condition = case_insensitive_like("#{table_name}.message", "%#{sanitized_query}%")
        like_sql = "SELECT #{table_name}.* FROM #{table_name} WHERE #{like_condition}"

        # Build FTS query for full-text matching
        fts_fragment = fts_search(query)
        fts_sql = "SELECT #{table_name}.* FROM #{table_name} #{fts_fragment}"

        # UNION both queries (DISTINCT removes duplicates)
        union_sql = "#{fts_sql} UNION #{like_sql}"
        Entry.from("(#{union_sql}) AS #{table_name}")
      end

      def fts_search(query)
        # PostgreSQL full-text search using tsvector
        sanitized_query = connection.quote(query.gsub(/[^\w\s]/, " "))
        <<~SQL.squish
          WHERE to_tsvector('english', COALESCE(message, '') || ' ' || COALESCE(extra_fields::text, ''))
          @@ plainto_tsquery('english', #{sanitized_query})
        SQL
      end

      def case_insensitive_like(column, pattern)
        # PostgreSQL uses ILIKE for case-insensitive matching
        "#{column} ILIKE #{connection.quote(pattern)}"
      end

      def claim_batch(batch_size)
        # PostgreSQL supports SKIP LOCKED
        RawEntry.transaction do
          entries = RawEntry.where(parsed: false)
            .order(received_at: :asc)
            .limit(batch_size)
            .lock("FOR UPDATE SKIP LOCKED")
            .to_a

          return [] if entries.empty?

          # Mark as parsed
          entry_ids = entries.map(&:id)
          RawEntry.where(id: entry_ids).update_all(parsed: true, parsed_at: Time.current)

          entries
        end
      end

      def extract_json_field(column, field_name)
        # PostgreSQL JSONB operator
        "#{column}->>'#{field_name}'"
      end

      def facet_values(column)
        "SELECT DISTINCT #{column} FROM solid_log_entries WHERE #{column} IS NOT NULL ORDER BY #{column}"
      end

      def optimize!
        # Analyze tables for query planning
        execute("ANALYZE solid_log_entries")
        execute("ANALYZE solid_log_raw")
        execute("ANALYZE solid_log_fields")

        # Vacuum if needed (non-blocking)
        execute("VACUUM ANALYZE solid_log_entries")
      rescue ActiveRecord::StatementInvalid => e
        # VACUUM might fail if already running
        Rails.logger.warn("PostgreSQL vacuum warning: #{e.message}")
      end

      def database_size
        result = select_value(<<~SQL)
          SELECT pg_database_size(current_database())
        SQL
        result.to_i
      end

      def supports_skip_locked?
        true
      end

      def supports_native_json?
        true  # JSONB
      end

      def supports_full_text_search?
        true  # tsvector/tsquery
      end

      def configure!
        # Set optimal PostgreSQL settings for logging workload
        execute("SET work_mem = '64MB'") rescue nil
        execute("SET maintenance_work_mem = '256MB'") rescue nil
      end

      def timestamp_to_epoch_sql(column)
        "EXTRACT(EPOCH FROM #{column})::bigint"
      end

      # PostgreSQL-specific methods
      def create_fts_index_sql
        <<~SQL
          CREATE INDEX IF NOT EXISTS idx_entries_fts
          ON solid_log_entries
          USING GIN (to_tsvector('english', COALESCE(message, '') || ' ' || COALESCE(extra_fields::text, '')))
        SQL
      end

      def create_json_indexes_sql
        # GIN index for JSONB queries
        [
          <<~SQL
            CREATE INDEX IF NOT EXISTS idx_entries_extra_fields
            ON solid_log_entries
            USING GIN (extra_fields jsonb_path_ops)
          SQL
        ]
      end

      # Bulk insert optimization for PostgreSQL
      def bulk_insert(table_name, records)
        return if records.empty?

        columns = records.first.keys
        values_sql = records.map do |record|
          "(#{columns.map { |col| connection.quote(record[col]) }.join(', ')})"
        end.join(", ")

        execute(<<~SQL)
          INSERT INTO #{table_name} (#{columns.join(', ')})
          VALUES #{values_sql}
        SQL
      end
    end
  end
end
