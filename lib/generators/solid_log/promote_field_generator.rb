require "rails/generators"
require "rails/generators/active_record"

module SolidLog
  module Generators
    class PromoteFieldGenerator < Rails::Generators::NamedBase
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      class_option :type, type: :string, default: "string",
                   desc: "Field type (string, number, boolean, datetime)"

      def create_migration
        migration_template "promote_field_migration.rb.tt",
                          "db/log_migrate/#{migration_file_name}.rb"
      end

      def show_instructions
        say "Migration created!", :green
        say ""
        say "Next steps:"
        say "  1. Review the migration: db/log_migrate/#{migration_file_name}.rb"
        say "  2. Run: rails db:migrate:log"
        say "  3. Update your queries to use the new column"
        say ""
        say "Note: The field will remain in extra_fields JSON for backward compatibility."
      end

      private

      def migration_file_name
        "add_#{file_name}_to_solid_log_entries"
      end

      def migration_class_name
        "Add#{class_name}ToSolidLogEntries"
      end

      def column_name
        file_name
      end

      def column_type
        case options[:type]
        when "number"
          "decimal"
        when "boolean"
          "boolean"
        when "datetime"
          "datetime"
        else
          "string"
        end
      end

      def backfill_sql
        case options[:type]
        when "number"
          "CAST(json_extract(extra_fields, '$.#{column_name}') AS REAL)"
        when "boolean"
          "CAST(json_extract(extra_fields, '$.#{column_name}') AS INTEGER)"
        when "datetime"
          "datetime(json_extract(extra_fields, '$.#{column_name}'))"
        else
          "json_extract(extra_fields, '$.#{column_name}')"
        end
      end
    end
  end
end
