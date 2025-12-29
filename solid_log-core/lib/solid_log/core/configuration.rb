module SolidLog
  module Core
    class Configuration
      attr_accessor :database_url,
                    :retention_days,
                    :error_retention_days,
                    :max_batch_size,
                    :parser_batch_size,
                    :parser_concurrency,
                    :auto_promote_fields,
                    :field_promotion_threshold,
                    :facet_cache_ttl,
                    :live_tail_mode

      def initialize
        # Load from ENV vars with defaults
        @database_url = ENV["SOLIDLOG_DATABASE_URL"] || ENV["DATABASE_URL"]
        @retention_days = env_to_int("SOLIDLOG_RETENTION_DAYS", 30)
        @error_retention_days = env_to_int("SOLIDLOG_ERROR_RETENTION_DAYS", 90)
        @max_batch_size = env_to_int("SOLIDLOG_MAX_BATCH_SIZE", 1000) # For API ingestion
        @parser_batch_size = env_to_int("SOLIDLOG_PARSER_BATCH_SIZE", 200) # Number of raw entries to parse per job
        @parser_concurrency = env_to_int("SOLIDLOG_PARSER_CONCURRENCY", 5)
        @auto_promote_fields = env_to_bool("SOLIDLOG_AUTO_PROMOTE_FIELDS", false)
        @field_promotion_threshold = env_to_int("SOLIDLOG_FIELD_PROMOTION_THRESHOLD", 1000)
        @facet_cache_ttl = env_to_int("SOLIDLOG_FACET_CACHE_TTL", 300) # seconds (5 minutes)
        @live_tail_mode = env_to_symbol("SOLIDLOG_LIVE_TAIL_MODE", :disabled) # :websocket, :polling, or :disabled
      end

      # Check if database is configured
      def database_configured?
        database_url.present?
      end

      # Get cache TTL in seconds
      def cache_ttl_seconds
        facet_cache_ttl.to_i
      end

      private

      def env_to_int(key, default = nil)
        value = ENV[key]
        return default if value.nil? || value.empty?
        value.to_i
      end

      def env_to_bool(key, default = false)
        value = ENV[key]
        return default if value.nil? || value.empty?
        ["true", "1", "yes", "on"].include?(value.downcase)
      end

      def env_to_symbol(key, default = nil)
        value = ENV[key]
        return default if value.nil? || value.empty?
        value.to_sym
      end
    end
  end
end
