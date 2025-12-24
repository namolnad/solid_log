module SolidLog
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Install SolidLog configuration and schema"

      def copy_initializer
        template "solid_log.rb", "config/initializers/solid_log.rb"
      end

      def copy_schema
        # Copy to db/log_structure.sql (Rails convention for :log database)
        copy_file File.expand_path("../../../../db/structure.sql", __dir__), "db/log_structure.sql"
      end

      def generate_triggers
        generate "solid_log:triggers"
      end

      def show_readme
        readme "README" if behavior == :invoke
      end

      private

      def readme(file)
        puts <<~README

          ====================================================================
          SolidLog has been installed! 🎉
          ====================================================================

          Next steps:

          1. Setup the log database:
             rails db:create:log db:schema:load:log

             This will create the database, load the schema (db/log_structure.sql),

          2. Create an API token for log ingestion:
             rails solid_log:create_token["Production API"]

          3. Mount the engine in your routes (config/routes.rb):
             mount SolidLog::Engine => "/admin/logs"

          4. Configure your app to send logs via HTTP:
             POST http://localhost:3000/admin/logs/api/v1/ingest
             Header: Authorization: Bearer YOUR_TOKEN

          5. Set up the parser worker (process raw logs):
             Add to crontab or scheduler:
             */5 * * * * cd #{Dir.pwd} && bundle exec rails solid_log:parse_logs

          6. Optional: Set up retention cleanup (delete old logs):
             0 2 * * * cd #{Dir.pwd} && bundle exec rails solid_log:retention[30]

          ====================================================================
          Documentation:
          - View health: rails solid_log:health
          - List tokens: rails solid_log:list_tokens
          - View stats:  rails solid_log:stats
          - Access UI:   http://localhost:3000/admin/logs
          ====================================================================

        README
      end

      def adapter_name
        ActiveRecord::Base.connection_db_config.adapter
      end
    end
  end
end
