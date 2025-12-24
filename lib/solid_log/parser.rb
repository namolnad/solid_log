module SolidLog
  class Parser
    STANDARD_FIELDS = %w[
      timestamp created_at occurred_at time
      level severity
      message msg text
      request_id
      job_id
      duration duration_ms
      status status_code
      controller
      action
      path
      method http_method
      app application
      env environment
    ].freeze

    VALID_LEVELS = %w[debug info warn error fatal unknown].freeze

    # Instance method for parsing (used by tests and jobs)
    def parse(raw_json)
      return nil if raw_json.blank?

      payload = JSON.parse(raw_json)
      return nil if payload.blank?

      extract_fields(payload)
    rescue JSON::ParserError
      nil
    end

    # Class method for parsing (for convenience)
    def self.parse(raw_json)
      new.parse(raw_json)
    end

    private

    # Extract standard and dynamic fields from payload
    def extract_fields(payload)
      standard = extract_standard_fields(payload)
      dynamic = extract_dynamic_fields(payload, standard.keys)

      # Return extra_fields as hash (ParserJob will convert to JSON)
      result = standard.merge(extra_fields: dynamic.empty? ? {} : dynamic)

      result
    end

    # Extract known/standard fields
    def extract_standard_fields(payload)
      fields = {}

      # Timestamp (required)
      fields[:created_at] = extract_timestamp(payload)

      # Level (required, default to info)
      fields[:level] = normalize_level(payload["level"] || payload["severity"] || "info")

      # Message
      fields[:message] = payload["message"] || payload["msg"] || payload["text"]

      # App and env
      fields[:app] = payload["app"] || payload["application"]
      fields[:env] = payload["env"] || payload["environment"]

      # Correlation IDs
      fields[:request_id] = payload["request_id"]
      fields[:job_id] = payload["job_id"]

      # HTTP/Controller fields
      fields[:controller] = payload["controller"]
      fields[:action] = payload["action"]
      fields[:path] = payload["path"]
      fields[:method] = payload["method"] || payload["http_method"]

      # Performance fields
      fields[:duration] = extract_duration(payload)
      fields[:status_code] = extract_status_code(payload)

      # Remove nil values
      fields.compact
    end

    # Extract dynamic fields (anything not in standard fields)
    def extract_dynamic_fields(payload, standard_keys)
      dynamic = payload.dup

      # Remove standard fields
      STANDARD_FIELDS.each { |f| dynamic.delete(f) }
      standard_keys.each { |k| dynamic.delete(k.to_s) }

      dynamic
    end

    # Normalize log level to standard values
    def normalize_level(level)
      return "info" if level.blank?

      level_str = level.to_s.downcase
      VALID_LEVELS.include?(level_str) ? level_str : "info"
    end

    # Extract timestamp from various field names
    def extract_timestamp(payload)
      timestamp_fields = %w[timestamp created_at occurred_at time]

      timestamp_fields.each do |field|
        value = payload[field]
        next if value.blank?

        begin
          return Time.parse(value) if value.is_a?(String)
          # Handle both seconds and milliseconds
          if value.is_a?(Numeric)
            return value > 10_000_000_000 ? Time.at(value / 1000.0) : Time.at(value)
          end
          return value if value.is_a?(Time) || value.is_a?(DateTime)
        rescue ArgumentError
          next
        end
      end

      # Fallback to current time
      Time.current
    end

    # Extract duration in milliseconds
    def extract_duration(payload)
      duration = payload["duration"] || payload["duration_ms"]
      return nil if duration.blank?

      duration.to_f
    end

    # Extract HTTP status code
    def extract_status_code(payload)
      status = payload["status"] || payload["status_code"]
      return nil if status.blank?

      status.to_i
    end

    # Track fields in the registry
    def track_fields(payload)
      payload.each do |key, value|
        next if STANDARD_FIELDS.include?(key)

        SolidLog.without_logging do
          field = Field.find_or_initialize_by(name: key)
          field.field_type ||= infer_type(value)
          field.usage_count ||= 0
          field.usage_count += 1
          field.last_seen_at = Time.current
          field.save if field.changed?
        end
      end
    rescue => e
      # Silently fail if field tracking has issues
      Rails.logger.debug("SolidLog: Failed to track fields: #{e.message}") if defined?(Rails)
    end

    # Infer the type of a value
    def infer_type(value)
      case value
      when TrueClass, FalseClass
        "boolean"
      when Integer, Float
        "number"
      when Time, DateTime, Date
        "datetime"
      else
        "string"
      end
    end
  end
end
