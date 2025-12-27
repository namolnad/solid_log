module SolidLog
  class ParserJob < ApplicationJob
    queue_as :default

    # Process a batch of unparsed raw entries
    def perform(batch_size: 100)
      SolidLog.without_logging do
        # Claim a batch of unparsed entries
        raw_entries = RawEntry.claim_batch(batch_size: batch_size)

        return if raw_entries.empty?

        Rails.logger.info "SolidLog::ParserJob: Processing #{raw_entries.size} raw entries"

        # Process each entry
        entries_to_insert = []
        fields_to_track = {}

        raw_entries.each do |raw_entry|
          begin
            # Parse the raw payload
            parsed = Parser.parse(raw_entry.payload)

            # Extract dynamic fields for field registry
            extra_fields = parsed.delete(:extra_fields) || {}
            track_fields(fields_to_track, extra_fields)

            # Prepare entry for insertion
            entry_data = {
              raw_id: raw_entry.id,
              timestamp: parsed[:timestamp],
              created_at: Time.current, # When entry was parsed/created
              level: parsed[:level],
              app: parsed[:app],
              env: parsed[:env],
              message: parsed[:message],
              request_id: parsed[:request_id],
              job_id: parsed[:job_id],
              duration: parsed[:duration],
              status_code: parsed[:status_code],
              controller: parsed[:controller],
              action: parsed[:action],
              path: parsed[:path],
              method: parsed[:method],
              extra_fields: extra_fields.to_json
            }

            entries_to_insert << entry_data

            # Mark raw entry as parsed
            raw_entry.mark_parsed!
          rescue StandardError => e
            Rails.logger.error "SolidLog::ParserJob: Failed to parse entry #{raw_entry.id}: #{e.message}"
            Rails.logger.error e.backtrace.join("\n")
            # Leave entry unparsed so it can be retried or investigated
          end
        end

        # Bulk insert parsed entries
        if entries_to_insert.any?
          Entry.insert_all(entries_to_insert)
          Rails.logger.info "SolidLog::ParserJob: Inserted #{entries_to_insert.size} entries"
        end

        # Update field registry
        update_field_registry(fields_to_track)
      end
    end

    private

    # Track field occurrences for the registry
    def track_fields(fields_hash, extra_fields)
      extra_fields.each do |key, value|
        fields_hash[key] ||= { values: [], count: 0 }
        fields_hash[key][:count] += 1
        fields_hash[key][:type] ||= infer_field_type(value)
      end
    end

    # Update the field registry with tracked fields
    def update_field_registry(fields_hash)
      fields_hash.each do |name, data|
        field = Field.find_or_initialize_by(name: name)
        field.field_type ||= data[:type]
        field.usage_count += data[:count]
        field.last_seen_at = Time.current
        field.save!
      end
    end

    # Infer field type from value
    def infer_field_type(value)
      case value
      when String
        "string"
      when Numeric
        "number"
      when TrueClass, FalseClass
        "boolean"
      when Time, DateTime, Date
        "datetime"
      when Array
        "array"
      when Hash
        "object"
      else
        "string"
      end
    end
  end
end
