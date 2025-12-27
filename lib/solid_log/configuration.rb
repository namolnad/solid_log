module SolidLog
  class Configuration
    attr_accessor :retention_days,
                  :error_retention_days,
                  :max_batch_size,
                  :parser_concurrency,
                  :facet_cache_ttl,
                  :authentication_method,
                  :ui_enabled,
                  :auto_promote_fields,
                  :field_promotion_threshold,
                  :client_token,
                  :ingestion_url,
                  :stream_view_style,
                  :live_tail_mode

    def initialize
      @retention_days = 30
      @error_retention_days = 90
      @max_batch_size = 1000
      @parser_concurrency = 5
      @facet_cache_ttl = 5.minutes
      @authentication_method = :basic
      @ui_enabled = true
      @auto_promote_fields = false
      @field_promotion_threshold = 1000
      @client_token = nil
      @ingestion_url = nil
      @stream_view_style = :compact # :compact or :expanded
      @live_tail_mode = :disabled # :websocket, :polling, or :disabled
    end
  end
end
