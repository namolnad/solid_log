class CreateSolidLogRaw < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_log_raw do |t|
      t.datetime :received_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.integer :token_id, null: false
      t.text :raw_payload, null: false
      t.boolean :parsed, default: false, null: false
      t.datetime :parsed_at
    end

    add_index :solid_log_raw, [ :parsed, :received_at ], name: "idx_raw_unparsed"
    add_index :solid_log_raw, :token_id, name: "idx_raw_token"
    add_index :solid_log_raw, :received_at, name: "idx_raw_received"
  end
end
