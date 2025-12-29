require "rails/generators/base"

module SolidLog
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      class_option :database, type: :string, default: nil, desc: "Database adapter (sqlite, postgresql, mysql)"

      desc "Install SolidLog configuration, migrations, and database structure"

      def copy_migrations
        say "Copying SolidLog migrations...", :green

        # Create log_migrate directory
        empty_directory "db/log_migrate"

        # Copy all migrations from solid_log-core
        migrations_path = File.expand_path("../../../../db/log_migrate", __dir__)
        Dir[File.join(migrations_path, "*.rb")].each do |file|
          copy_file file, "db/log_migrate/#{File.basename(file)}"
        end
      end

      def copy_structure_file
        database = options[:database] || detect_database_adapter

        say "Copying #{database} database structure file...", :green

        structure_file = case database
        when "sqlite", "sqlite3"
          "log_structure_sqlite.sql"
        when "postgresql", "postgres", "pg"
          "log_structure_postgresql.sql"
        when "mysql", "mysql2", "trilogy"
          "log_structure_mysql.sql"
        else
          say "Unknown database: #{database}, skipping structure file", :yellow
          return
        end

        source_path = File.expand_path("../../../../db/#{structure_file}", __dir__)
        if File.exist?(source_path)
          copy_file source_path, "db/log_structure.sql"
        else
          say "Structure file not found: #{structure_file}", :red
        end
      end

      def create_initializer
        say "Creating initializer...", :green
        template "solid_log.rb.tt", "config/initializers/solid_log.rb"
      end

      def show_instructions
        say "\n" + "="*80, :green
        say "SolidLog Installation Complete! 🎉", :green
        say "="*80 + "\n", :green

        say "Next steps:", :yellow
        say ""
        say "1. Configure your database in config/database.yml:", :cyan
        say "   Add a :log database connection. Example:"
        say ""
        say "   production:"
        say "     primary:"
        say "       adapter: sqlite3"
        say "       database: storage/production.sqlite3"
        say "     log:"
        say "       adapter: sqlite3"
        say "       database: storage/production_log.sqlite3"
        say "       migrations_paths: db/log_migrate"
        say ""
        say "2. Create databases and run migrations:", :cyan
        say "   rails db:create"
        say "   rails db:migrate"
        say ""
        say "3. (Alternative) Load structure file:", :cyan
        say "   rails db:create"
        say "   rails db:schema:load SCHEMA=db/log_structure.sql DATABASE=log"
        say ""
        say "4. Enable WAL mode for SQLite (HIGHLY RECOMMENDED):", :cyan
        say "   Already configured in config/initializers/solid_log.rb"
        say "   Provides 3.4x faster performance for crash-safe logging!"
        say ""
        say "5. Configure DirectLogger for your app (recommended):", :cyan
        say "   See config/initializers/solid_log.rb for examples"
        say "   DirectLogger is 9x faster than individual inserts"
        say ""
        say "6. Create an API token:", :cyan
        say "   rails solid_log:create_token[\"Production API\"]"
        say ""
        say "7. Mount the UI (if using solid_log-ui):", :cyan
        say "   Add to config/routes.rb:"
        say "   mount SolidLog::UI::Engine => '/admin/logs'"
        say ""

        say "Useful commands:", :yellow
        say "  rails solid_log:stats          # View log statistics"
        say "  rails solid_log:health         # Check system health"
        say "  rails solid_log:list_tokens    # List API tokens"
        say "  rails solid_log:parse_logs     # Parse raw logs"
        say "  rails solid_log:retention[30]  # Clean up old logs"
        say ""
        say "Documentation:", :green
        say "  README:      README.md"
        say "  Quickstart:  QUICKSTART.md"
        say "  Benchmarks:  solid_log-core/BENCHMARK_RESULTS.md"
        say "="*80 + "\n", :green
      end

      private

      def detect_database_adapter
        if defined?(ActiveRecord::Base)
          adapter = ActiveRecord::Base.connection_db_config.adapter rescue nil
          return adapter if adapter
        end

        # Try to read from database.yml
        if File.exist?("config/database.yml")
          require "yaml"
          db_config = YAML.load_file("config/database.yml")
          env = ENV["RAILS_ENV"] || "development"
          adapter = db_config.dig(env, "adapter") || db_config.dig(env, "primary", "adapter")
          return adapter if adapter
        end

        # Default to sqlite
        "sqlite3"
      end
    end
  end
end
