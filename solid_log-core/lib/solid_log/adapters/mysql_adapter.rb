module SolidLog
  module Adapters
    class MysqlAdapter < BaseAdapter
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
        # MySQL FULLTEXT search
        sanitized_query = connection.quote(query)
        <<~SQL.squish
          WHERE MATCH(message, extra_fields) AGAINST(#{sanitized_query} IN NATURAL LANGUAGE MODE)
        SQL
      end

      def case_insensitive_like(column, pattern)
        # MySQL LIKE is case-insensitive by default with default collation
        "#{column} LIKE #{connection.quote(pattern)}"
      end

      def claim_batch(batch_size)
        # MySQL 8.0+ supports SKIP LOCKED
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
      rescue ActiveRecord::StatementInvalid => e
        # Fallback for MySQL < 8.0 without SKIP LOCKED
        if e.message.include?("syntax error")
          claim_batch_legacy(batch_size)
        else
          raise
        end
      end

      def extract_json_field(column, field_name)
        # MySQL JSON_EXTRACT
        "JSON_UNQUOTE(JSON_EXTRACT(#{column}, '$.#{field_name}'))"
      end

      def facet_values(column)
        "SELECT DISTINCT #{column} FROM solid_log_entries WHERE #{column} IS NOT NULL ORDER BY #{column}"
      end

      def optimize!
        execute("OPTIMIZE TABLE solid_log_entries")
        execute("OPTIMIZE TABLE solid_log_raw")
        execute("ANALYZE TABLE solid_log_entries")
        execute("ANALYZE TABLE solid_log_raw")
      rescue ActiveRecord::StatementInvalid => e
        Rails.logger.warn("MySQL optimize warning: #{e.message}")
      end

      def database_size
        result = select_value(<<~SQL)
          SELECT SUM(data_length + index_length)
          FROM information_schema.TABLES
          WHERE table_schema = DATABASE()
          AND table_name LIKE 'solid_log_%'
        SQL
        result.to_i
      end

      def supports_skip_locked?
        # MySQL 8.0+
        version = connection.get_database_version
        version >= "8.0"
      end

      def supports_native_json?
        true  # MySQL 5.7+
      end

      def supports_full_text_search?
        true  # FULLTEXT indexes
      end

      def configure!
        # Set optimal MySQL settings
        execute("SET SESSION sql_mode = 'TRADITIONAL'") rescue nil
        execute("SET SESSION innodb_lock_wait_timeout = 50") rescue nil
      end

      def timestamp_to_epoch_sql(column)
        "UNIX_TIMESTAMP(#{column})"
      end

      # MySQL-specific methods
      def create_fts_index_sql
        <<~SQL
          CREATE FULLTEXT INDEX idx_entries_fts
          ON solid_log_entries(message, extra_fields)
        SQL
      end

      def create_json_indexes_sql
        # MySQL doesn't have native JSON indexes, use generated columns
        [
          # Example for common fields - these would be created via field promotion
          # "ALTER TABLE solid_log_entries ADD COLUMN user_id_virtual INT GENERATED ALWAYS AS (JSON_UNQUOTE(JSON_EXTRACT(extra_fields, '$.user_id'))) STORED",
          # "CREATE INDEX idx_entries_user_id ON solid_log_entries(user_id_virtual)"
        ]
      end

      # Bulk insert optimization for MySQL
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

      private

      def claim_batch_legacy(batch_size)
        # Fallback for MySQL < 8.0 without SKIP LOCKED
        RawEntry.transaction do
          ids = RawEntry.where(parsed: false)
            .order(received_at: :asc)
            .limit(batch_size)
            .lock
            .pluck(:id)

          return [] if ids.empty?

          RawEntry.where(id: ids).update_all(parsed: true, parsed_at: Time.current)
          RawEntry.where(id: ids).to_a
        end
      end
    end
  end
end
