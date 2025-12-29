module SolidLog
  module Core
    class ClientConfiguration
      attr_accessor :service_url,
                    :token,
                    :app_name,
                    :environment,
                    :batch_size,
                    :flush_interval,
                    :max_queue_size,
                    :retry_max_attempts,
                    :enabled

      def initialize
        @service_url = nil
        @token = nil
        @app_name = "app"
        @environment = "production"
        @batch_size = 100
        @flush_interval = 5 # seconds
        @max_queue_size = 10_000
        @retry_max_attempts = 3
        @enabled = true
      end

      def valid?
        service_url.present? && token.present?
      end
    end
  end
end
