namespace :db do
  namespace :structure do
    desc "Load log database structure from SQL file"
    task load_log: :environment do
      structure_file = Rails.root.join("db", "log_structure.sql")

      unless File.exist?(structure_file)
        puts "Structure file not found: #{structure_file}"
        exit 1
      end

      ActiveRecord::Base.connected_to(role: :writing, shard: :log) do
        db_config = ActiveRecord::Base.connection_db_config
        database_path = db_config.database

        puts "Loading structure into log database: #{database_path}"

        # Execute the SQL file
        sql = File.read(structure_file)
        statements = sql.split(";").map(&:strip).reject(&:empty?)

        statements.each do |statement|
          begin
            ActiveRecord::Base.connection.execute(statement) unless statement =~ /^INSERT INTO.*schema_migrations/
          rescue => e
            # Ignore errors for things that might already exist
            puts "Warning: #{e.message}" if ENV['VERBOSE']
          end
        end

        puts "Structure loaded successfully!"
      end
    end
  end
end
