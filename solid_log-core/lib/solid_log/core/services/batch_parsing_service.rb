# frozen_string_literal: true

module SolidLog
  module Core
    module Services
      # BatchParsingService processes batches of unparsed raw log entries.
      #
      # This service is the single source of truth for parsing logic, used by:
      # - Puma plugin (inline processing)
      # - ParseJob (Solid Queue / ActiveJob)
      # - solid_log-service (dedicated service process)
      #
      # @example Basic usage
      #   stats = BatchParsingService.process_batch(batch_size: 200)
      #   # => { processed: 150, inserted: 145, errors: 5 }
      #
      # @example With custom callback
      #   callback = ->(entry_ids) { puts "Processed #{entry_ids.size} entries" }
      #   BatchParsingService.process_batch(broadcast_callback: callback)
      class BatchParsingService
        # Process a batch of unparsed raw entries
        #
        # @param batch_size [Integer] Number of entries to process (default: config value)
        # @param logger [Logger] Logger instance (default: SolidLog.logger)
        # @param broadcast_callback [Proc] Callback for broadcasting new entries
        # @return [Hash] Statistics hash with :processed, :inserted, :errors keys
        def self.process_batch(batch_size: nil, logger: nil, broadcast_callback: nil)
          batch_size ||= SolidLog.configuration.parser_batch_size
          logger ||= SolidLog.logger

          stats = { processed: 0, inserted: 0, errors: 0 }

          SolidLog.without_logging do
            # Claim a batch of unparsed entries
            raw_entries = RawEntry.claim_batch(batch_size: batch_size)

            return stats if raw_entries.empty?

            # Log to STDERR to avoid recursion (only in debug mode)
            $stderr.puts "[SolidLog::BatchParsingService] Processing #{raw_entries.size} raw entries" if ENV["SOLIDLOG_DEBUG"]

            # Get promoted fields cache (for performance)
            promoted_fields = get_promoted_fields_cache

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

                # Populate promoted field columns
                populate_promoted_fields(entry_data, extra_fields, promoted_fields)

                entries_to_insert << entry_data
                stats[:processed] += 1
              rescue StandardError => e
                logger.error "SolidLog::BatchParsingService: Failed to parse entry #{raw_entry.id}: #{e.message}"
                logger.error e.backtrace.first(5).join("\n") if e.backtrace
                stats[:errors] += 1
                # Entry remains unparsed so it can be retried or investigated
              end
            end

            # Bulk insert parsed entries
            if entries_to_insert.any?
              raw_ids = entries_to_insert.map { |e| e[:raw_id] }

              Entry.insert_all(entries_to_insert)
              stats[:inserted] = entries_to_insert.size
              # Log to STDERR to avoid recursion (only in debug mode)
              $stderr.puts "[SolidLog::BatchParsingService] Inserted #{entries_to_insert.size} entries" if ENV["SOLIDLOG_DEBUG"]

              # Broadcast new entry IDs for live tail
              new_entry_ids = Entry.where(raw_id: raw_ids).pluck(:id)
              broadcast_entries(new_entry_ids, broadcast_callback, logger)
            end

            # Update field registry
            update_field_registry(fields_to_track, logger)
          end

          stats
        end

        private

        # Track field occurrences for the registry
        def self.track_fields(fields_hash, extra_fields)
          extra_fields.each do |key, value|
            fields_hash[key] ||= { values: [], count: 0 }
            fields_hash[key][:count] += 1
            fields_hash[key][:type] ||= infer_field_type(value)
          end
        end

        # Update the field registry with tracked fields
        def self.update_field_registry(fields_hash, logger)
          fields_hash.each do |name, data|
            field = Field.find_or_initialize_by(name: name)
            field.field_type ||= data[:type]
            field.usage_count += data[:count]
            field.last_seen_at = Time.current
            field.save!
          end
        rescue StandardError => e
          logger.error "SolidLog::BatchParsingService: Failed to update field registry: #{e.message}"
        end

        # Infer field type from value
        def self.infer_field_type(value)
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

        # Get cache of promoted fields and their types
        # Returns hash: { "field_name" => "field_type", ... }
        def self.get_promoted_fields_cache
          @promoted_fields_cache ||= {}
          @promoted_fields_cache_time ||= Time.at(0)

          # Refresh cache every 60 seconds
          if Time.current - @promoted_fields_cache_time > 60
            promoted = Field.promoted.pluck(:name, :field_type).to_h
            available_columns = Entry.column_names

            # Only include fields that have actual columns in the table
            @promoted_fields_cache = promoted.select { |name, _type| available_columns.include?(name) }
            @promoted_fields_cache_time = Time.current
          end

          @promoted_fields_cache
        rescue StandardError
          # If Field table doesn't exist yet or there's an error, return empty hash
          {}
        end

        # Populate promoted field columns in entry_data
        # Extracts values from extra_fields and adds them to entry_data
        # Note: values remain in extra_fields JSON for backward compatibility
        def self.populate_promoted_fields(entry_data, extra_fields, promoted_fields)
          promoted_fields.each do |field_name, field_type|
            next unless extra_fields.key?(field_name)

            value = extra_fields[field_name]
            next if value.nil?

            # Type coercion for promoted field
            begin
              typed_value = coerce_field_value(value, field_type)
              entry_data[field_name.to_sym] = typed_value
            rescue StandardError
              # If type coercion fails, skip this field
              # Field remains in extra_fields JSON
            end
          end
        end

        # Coerce a value to the specified field type
        def self.coerce_field_value(value, field_type)
          case field_type
          when "number"
            value.is_a?(Numeric) ? value : value.to_f
          when "boolean"
            [true, "true", "1", 1].include?(value)
          when "datetime"
            value.is_a?(Time) ? value : Time.parse(value.to_s)
          when "string"
            value.to_s
          when "array", "object"
            # Arrays and objects stored as JSON text
            value.is_a?(String) ? value : value.to_json
          else
            value
          end
        end

        # Broadcast new entries via callback or ActionCable
        def self.broadcast_entries(entry_ids, callback, logger)
          return if entry_ids.empty?

          # Try user-configured callback first
          if callback&.respond_to?(:call)
            callback.call(entry_ids)
            return
          end

          # Try configuration callback
          if SolidLog.configuration.after_entries_inserted&.respond_to?(:call)
            SolidLog.configuration.after_entries_inserted.call(entry_ids)
            return
          end

          # Fallback to ActionCable if available
          if defined?(ActionCable) && ActionCable.server
            ActionCable.server.broadcast(
              "solid_log_new_entries",
              { entry_ids: entry_ids }
            )
          end
        rescue StandardError => e
          # Silent failure - broadcasting is optional (log to STDERR to avoid recursion)
          $stderr.puts "[SolidLog::BatchParsingService] Broadcast failed: #{e.message}" if ENV["SOLIDLOG_DEBUG"]
        end
      end
    end
  end
end
