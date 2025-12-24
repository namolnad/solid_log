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
    SQL
  end
end
