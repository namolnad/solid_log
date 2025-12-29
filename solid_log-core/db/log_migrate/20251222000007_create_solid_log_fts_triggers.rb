class CreateSolidLogFtsTriggers < ActiveRecord::Migration[8.0]
  def up
    # SQLite FTS5 implementation
    execute <<~SQL
      CREATE VIRTUAL TABLE solid_log_entries_fts USING fts5(
        message,
        extra_fields,
        content='solid_log_entries',
        content_rowid='id'
      );
    SQL

    execute <<~SQL
      CREATE TRIGGER solid_log_entries_fts_insert AFTER INSERT ON solid_log_entries BEGIN
        INSERT INTO solid_log_entries_fts(rowid, message, extra_fields)
        VALUES (new.id, new.message, new.extra_fields);
      END;
    SQL

    execute <<~SQL
      CREATE TRIGGER solid_log_entries_fts_update AFTER UPDATE ON solid_log_entries BEGIN
        UPDATE solid_log_entries_fts
        SET message = new.message, extra_fields = new.extra_fields
        WHERE rowid = new.id;
      END;
    SQL

    execute <<~SQL
      CREATE TRIGGER solid_log_entries_fts_delete AFTER DELETE ON solid_log_entries BEGIN
        DELETE FROM solid_log_entries_fts WHERE rowid = old.id;
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS solid_log_entries_fts_delete"
    execute "DROP TRIGGER IF EXISTS solid_log_entries_fts_update"
    execute "DROP TRIGGER IF EXISTS solid_log_entries_fts_insert"
    execute "DROP TABLE IF EXISTS solid_log_entries_fts"
  end
end
