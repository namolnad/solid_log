module SolidLog
  module Adapters
    class AdapterFactory
      class << self
        def adapter
          @adapter ||= build_adapter
        end

        def reset!
          @adapter = nil
        end

        private

        def build_adapter
          connection = ActiveRecord::Base.connection
          adapter_name = connection.adapter_name.downcase

          case adapter_name
          when "sqlite"
            SqliteAdapter.new(connection)
          when "postgresql"
            PostgresqlAdapter.new(connection)
          when "mysql2", "trilogy"
            MysqlAdapter.new(connection)
          else
            raise "Unsupported database adapter: #{adapter_name}. " \
                  "SolidLog supports SQLite, PostgreSQL, and MySQL."
          end
        end
      end
    end
  end
end
