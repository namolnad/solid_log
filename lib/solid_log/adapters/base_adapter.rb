module SolidLog
  module Adapters
    class BaseAdapter
      def initialize(connection)
        @connection = connection
      end

      # Full-text search
      def fts_search(query)
        raise NotImplementedError, "#{self.class} must implement #fts_search"
      end

      # Claim unparsed entries with lock
      def claim_batch(batch_size)
        raise NotImplementedError, "#{self.class} must implement #claim_batch"
      end

      # JSON field extraction
      def extract_json_field(column, field_name)
        raise NotImplementedError, "#{self.class} must implement #extract_json_field"
      end

      # Facet query (distinct values)
      def facet_values(column)
        raise NotImplementedError, "#{self.class} must implement #facet_values"
      end

      # Optimize database
      def optimize!
        # Default: no-op
      end

      # Database size in bytes
      def database_size
        raise NotImplementedError, "#{self.class} must implement #database_size"
      end

      # Supports feature?
      def supports_skip_locked?
        false
      end

      def supports_native_json?
        false
      end

      def supports_full_text_search?
        false
      end

      # Database-specific configurations
      def configure!
        # Default: no-op
      end

      protected

      attr_reader :connection

      def execute(sql)
        connection.execute(sql)
      end

      def select_all(sql)
        connection.select_all(sql)
      end

      def select_value(sql)
        connection.select_value(sql)
      end
    end
  end
end
