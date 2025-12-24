class CreateSolidLogFacetCache < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_log_facet_cache do |t|
      t.string :cache_key, null: false
      t.text :cache_value, null: false
      t.datetime :expires_at
      t.timestamps
    end

    add_index :solid_log_facet_cache, :cache_key, unique: true, name: "idx_facet_cache_key"
    add_index :solid_log_facet_cache, :expires_at, name: "idx_facet_expires"
  end
end
