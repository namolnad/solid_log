class CreateSolidLogEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_log_entries do |t|
      t.integer :raw_id, null: false
      t.datetime :timestamp, null: false    # When the log event occurred
      t.datetime :created_at, null: false   # When the entry was parsed/created
      t.string :level, null: false
      t.string :app
      t.string :env
      t.text :message
      t.string :request_id
      t.string :job_id
      t.float :duration
      t.integer :status_code
      t.string :controller
      t.string :action
      t.string :path
      t.string :method
      t.text :extra_fields
    end

    add_index :solid_log_entries, :timestamp, order: { timestamp: :desc }, name: "idx_entries_timestamp"
    add_index :solid_log_entries, :level, name: "idx_entries_level"
    add_index :solid_log_entries, [ :app, :env, :timestamp ], order: { timestamp: :desc }, name: "idx_entries_app_env_time"
    add_index :solid_log_entries, :request_id, name: "idx_entries_request"
    add_index :solid_log_entries, :job_id, name: "idx_entries_job"
    add_index :solid_log_entries, :raw_id, name: "idx_entries_raw"
  end
end
