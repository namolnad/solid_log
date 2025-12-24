require "rails/generators"
require "rails/generators/active_record"

module SolidLog
  module Generators
    class TriggersGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Generate FTS triggers migration for SolidLog based on database adapter"

      def create_triggers_migration
        # Put migration in db/log_migrate for the :log database
        migration_template "fts_triggers_migration.rb.tt", "db/log_migrate/create_solid_log_fts_triggers.rb"
      end

      private

      def adapter_name
        ActiveRecord::Base.connection_db_config.adapter
      end

      def sqlite_adapter?
        adapter_name == "sqlite3"
      end

      def postgresql_adapter?
        adapter_name == "postgresql"
      end

      def mysql_adapter?
        adapter_name.in?(["mysql2", "trilogy"])
      end
    end
  end
end
