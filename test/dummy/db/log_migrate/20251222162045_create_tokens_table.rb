class CreateTokensTable < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_log_tokens do |t|
      t.string :name, null: false
      t.string :token_hash, null: false
      t.datetime :last_used_at
      t.timestamps
    end

    add_index :solid_log_tokens, :token_hash, unique: true, name: "idx_tokens_hash"
    add_index :solid_log_tokens, :name, name: "idx_tokens_name"
  end
end
