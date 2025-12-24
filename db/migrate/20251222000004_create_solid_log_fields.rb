class CreateSolidLogFields < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_log_fields do |t|
      t.string :name, null: false
      t.string :field_type, null: false
      t.string :filter_type, default: "multiselect", null: false
      t.integer :usage_count, default: 0, null: false
      t.datetime :last_seen_at
      t.boolean :promoted, default: false, null: false
      t.timestamps
    end

    add_index :solid_log_fields, :name, unique: true, name: "idx_fields_name"
    add_index :solid_log_fields, :promoted, name: "idx_fields_promoted"
    add_index :solid_log_fields, :usage_count, name: "idx_fields_usage"
  end
end
