module SolidLog
  module Core
    class LogrageFormatter
      # Format Lograge output for SolidLog
      def call(data)
        # Lograge data is already a hash with structured fields
        # Just ensure we have the required fields

        formatted = {
          timestamp: Time.current.iso8601,
          level: infer_level(data),
          message: build_message(data),
          app: Client.configuration.app_name,
          env: Client.configuration.environment
        }

        # Add Lograge fields
        formatted.merge!(extract_lograge_fields(data))

        # Send to client
        Client.log(formatted)

        # Return JSON for Rails logger (if also logging to file)
        JSON.generate(formatted)
      end

      private

      def infer_level(data)
        # Determine log level based on status code or error
        if data[:status].to_i >= 500
          "error"
        elsif data[:status].to_i >= 400
          "warn"
        elsif data[:exception].present?
          "error"
        else
          "info"
        end
      end

      def build_message(data)
        parts = []

        # HTTP method and path
        parts << "#{data[:method]} #{data[:path]}" if data[:method] && data[:path]

        # Status code
        parts << "(#{data[:status]})" if data[:status]

        # Duration
        parts << "#{data[:duration]}ms" if data[:duration]

        # Controller and action
        if data[:controller] && data[:action]
          parts << "#{data[:controller]}##{data[:action]}"
        end

        parts.join(" ")
      end

      def extract_lograge_fields(data)
        fields = {}

        # Standard Lograge fields
        fields[:method] = data[:method] if data[:method]
        fields[:path] = data[:path] if data[:path]
        fields[:controller] = data[:controller] if data[:controller]
        fields[:action] = data[:action] if data[:action]
        fields[:status_code] = data[:status] if data[:status]
        fields[:duration] = data[:duration] if data[:duration]

        # Request ID for correlation
        fields[:request_id] = data[:request_id] if data[:request_id]

        # View rendering time
        fields[:view_runtime] = data[:view] if data[:view]
        fields[:db_runtime] = data[:db] if data[:db]

        # Params (be careful with sensitive data)
        fields[:params] = data[:params] if data[:params]

        # Remote IP
        fields[:ip] = data[:remote_ip] if data[:remote_ip]

        # User agent
        fields[:user_agent] = data[:user_agent] if data[:user_agent]

        # Any other custom fields
        data.except(:method, :path, :controller, :action, :status, :duration,
                   :request_id, :view, :db, :params, :remote_ip, :user_agent).each do |key, value|
          fields[key] = value unless value.nil?
        end

        fields
      end
    end
  end
end
