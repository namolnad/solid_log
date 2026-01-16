# frozen_string_literal: true

module SolidLog
  module Core
    # Runs pending ActiveRecord migrations for the log database
    # Used by standalone service to auto-migrate on startup
    class MigrationRunner
    class << self
      # Run all pending migrations
      # @param migration_paths [Array<String>] Paths to search for migrations (optional)
      # @return [Boolean] true if migrations ran successfully, false otherwise
      def run_pending_migrations(migration_paths: nil)
        paths = migration_paths || default_migration_paths
        paths = Array(paths).select { |p| Dir.exist?(p) }

        if paths.empty?
          SolidLog.logger&.warn("No migration directories found, skipping migrations")
          return true
        end

        SolidLog.logger&.info("Checking for pending migrations in: #{paths.join(', ')}")

        begin
          # Create schema_migrations table if it doesn't exist
          ensure_schema_migrations_table!

          # Get currently applied migrations
          applied_versions = get_applied_versions

          # Find all migration files
          migration_files = find_migration_files(paths)

          # Filter to pending migrations
          pending = migration_files.reject { |file| applied_versions.include?(version_from_file(file)) }

          if pending.empty?
            SolidLog.logger&.info("No pending migrations found")
            return true
          end

          SolidLog.logger&.info("Found #{pending.size} pending migration(s)")

          # Run each pending migration
          pending.sort.each do |migration_file|
            run_migration_file(migration_file)
          end

          SolidLog.logger&.info("Successfully ran #{pending.size} migration(s)")
          true
        rescue => e
          SolidLog.logger&.error("Migration failed: #{e.message}")
          SolidLog.logger&.error(e.backtrace.join("\n"))
          false
        end
      end

      # Check if there are pending migrations
      # @param migration_paths [Array<String>] Paths to search for migrations (optional)
      # @return [Boolean] true if pending migrations exist
      def pending_migrations?(migration_paths: nil)
        paths = migration_paths || default_migration_paths
        paths = Array(paths).select { |p| Dir.exist?(p) }

        return false if paths.empty?

        applied_versions = get_applied_versions
        migration_files = find_migration_files(paths)

        migration_files.any? { |file| !applied_versions.include?(version_from_file(file)) }
      end

      private

      # Default paths to search for migrations
      def default_migration_paths
        paths = []

        # Rails app log_migrate directory
        paths << Rails.root.join("db", "log_migrate") if defined?(Rails)

        # Service directory
        paths << File.expand_path("../../../../../solid_log-service/db/log_migrate", __FILE__)

        # Core gem directory
        paths << File.expand_path("../../../../db/log_migrate", __FILE__)

        paths
      end

      # Ensure schema_migrations table exists
      def ensure_schema_migrations_table!
        ActiveRecord::Base.connection.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS schema_migrations (
            version VARCHAR(255) NOT NULL PRIMARY KEY
          )
        SQL
      end

      # Get list of applied migration versions
      def get_applied_versions
        ActiveRecord::Base.connection
          .execute("SELECT version FROM schema_migrations")
          .map { |row| row.is_a?(Hash) ? row["version"] : row[0] }
          .to_set
      end

      # Find all migration files in given paths
      def find_migration_files(paths)
        paths.flat_map do |path|
          Dir[File.join(path, "*.rb")]
        end.uniq
      end

      # Extract version (timestamp) from migration filename
      def version_from_file(filepath)
        File.basename(filepath).match(/^(\d+)_/)[1]
      end

      # Run a single migration file
      def run_migration_file(filepath)
        version = version_from_file(filepath)
        filename = File.basename(filepath, ".rb")

        SolidLog.logger&.info("Running migration: #{filename}")

        # Load and instantiate migration
        load filepath
        migration_name = filename.split("_", 2).last.camelize
        migration_class = migration_name.constantize

        # Run migration
        migration = migration_class.new
        ActiveRecord::Base.connection.transaction do
          migration.migrate(:up)

          # Record migration as applied
          ActiveRecord::Base.connection.execute(
            "INSERT INTO schema_migrations (version) VALUES ('#{version}')"
          )
        end

        SolidLog.logger&.info("Completed migration: #{filename}")
      end
    end
  end
  end
end
