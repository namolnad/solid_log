module SolidLog
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Install SolidLog configuration and migrations"

      def copy_initializer
        template "solid_log.rb", "config/initializers/solid_log.rb"
      end

      def copy_migrations
        rake "solid_log:install:migrations"
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

          1. Run migrations to create the log database:
             rails db:migrate

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
    end
  end
end
