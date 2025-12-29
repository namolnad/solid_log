module SolidLog
  module Adapters
    class SqliteAdapter < BaseAdapter
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
        # SQLite FTS5 search
        sanitized_query = connection.quote(query)
        <<~SQL.squish
          JOIN solid_log_entries_fts
          ON solid_log_entries.id = solid_log_entries_fts.rowid
          WHERE solid_log_entries_fts MATCH #{sanitized_query}
        SQL
      end

      def case_insensitive_like(column, pattern)
        # SQLite uses LIKE with COLLATE NOCASE for case-insensitive matching
        "#{column} LIKE #{connection.quote(pattern)} COLLATE NOCASE"
      end

      def claim_batch(batch_size)
        # SQLite doesn't support SKIP LOCKED, so we use a different approach
        # Get IDs first, then update them
        RawEntry.transaction do
          ids = RawEntry.where(parsed: false)
            .order(received_at: :asc)
            .limit(batch_size)
            .lock
            .pluck(:id)

          return [] if ids.empty?

          # Mark as parsed immediately
          RawEntry.where(id: ids).update_all(parsed: true, parsed_at: Time.current)

          # Return the entries
          RawEntry.where(id: ids).to_a
        end
      end

      def extract_json_field(column, field_name)
        "json_extract(#{column}, '$.#{field_name}')"
      end

      def facet_values(column)
        "SELECT DISTINCT #{column} FROM solid_log_entries WHERE #{column} IS NOT NULL ORDER BY #{column}"
      end

      def optimize!
        execute("PRAGMA optimize")
        execute("PRAGMA wal_checkpoint(TRUNCATE)")
      end

      def database_size
        db_path = connection.instance_variable_get(:@config)[:database]
        File.size(db_path) rescue 0
      end

      def supports_skip_locked?
        false
      end

      def supports_native_json?
        false
      end

      def supports_full_text_search?
        true  # FTS5
      end

      def configure!
        execute("PRAGMA journal_mode=WAL")
        execute("PRAGMA synchronous=NORMAL")
        execute("PRAGMA busy_timeout=5000")
        execute("PRAGMA cache_size=-64000")  # 64MB
        execute("PRAGMA temp_store=MEMORY")
        execute("PRAGMA mmap_size=268435456")  # 256MB
      rescue ActiveRecord::StatementInvalid => e
        # Some pragmas may not be supported in all SQLite versions
        Rails.logger.warn("SQLite configuration warning: #{e.message}")
      end

      def timestamp_to_epoch_sql(column)
        "strftime('%s', #{column})"
      end

      # FTS5-specific methods
      def create_fts_table_sql
        <<~SQL
          CREATE VIRTUAL TABLE IF NOT EXISTS solid_log_entries_fts USING fts5(
            message,
            extra_text,
            content='solid_log_entries',
            content_rowid='id'
          )
        SQL
      end

      def create_fts_triggers_sql
        [
          # Insert trigger
          <<~SQL,
            CREATE TRIGGER IF NOT EXISTS solid_log_entries_fts_insert
            AFTER INSERT ON solid_log_entries
            BEGIN
              INSERT INTO solid_log_entries_fts(rowid, message, extra_text)
              VALUES (new.id, new.message, new.extra_fields);
            END
          SQL

          # Update trigger
          <<~SQL,
            CREATE TRIGGER IF NOT EXISTS solid_log_entries_fts_update
            AFTER UPDATE ON solid_log_entries
            BEGIN
              UPDATE solid_log_entries_fts
              SET message = new.message, extra_text = new.extra_fields
              WHERE rowid = new.id;
            END
          SQL

          # Delete trigger
          <<~SQL
            CREATE TRIGGER IF NOT EXISTS solid_log_entries_fts_delete
            AFTER DELETE ON solid_log_entries
            BEGIN
              DELETE FROM solid_log_entries_fts WHERE rowid = old.id;
            END
          SQL
        ]
      end
    end
  end
end
