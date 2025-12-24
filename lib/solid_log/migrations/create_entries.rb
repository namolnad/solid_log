class CreateEntries < ActiveRecord::Migration[7.1]
  def change
    create_table :entries do |t|
      t.datetime :created_at, null: false
      t.string :level
      t.string :progname
      t.text :message
    end

    execute <<~SQL
      CREATE VIRTUAL TABLE entries_fts USING fts5(message);

      CREATE TRIGGER IF NOT EXISTS entries_ai AFTER INSERT ON entries BEGIN
        INSERT INTO entries_fts(rowid, message) VALUES (new.id, new.message);
      END;

      CREATE TRIGGER IF NOT EXISTS entries_au AFTER UPDATE ON entries BEGIN
        UPDATE entries_fts SET message = new.message WHERE rowid = old.id;
      END;

      CREATE TRIGGER IF NOT EXISTS entries_ad AFTER DELETE ON entries BEGIN
        DELETE FROM entries_fts WHERE rowid = old.id;
      END;
    SQL
  end
end
