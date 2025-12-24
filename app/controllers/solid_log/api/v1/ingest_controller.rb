module SolidLog
  module Api
    module V1
      class IngestController < Api::BaseController
        # POST /api/v1/ingest
        # Accepts single log entry (hash) or batch (array of hashes)
        def create
          payload = params[:_json] || parse_ndjson_body

          if payload.blank?
            render json: { error: "Empty payload" }, status: :bad_request
            return
          end

          entries = Array.wrap(payload)

          if entries.size > max_batch_size
            render json: {
              error: "Batch too large",
              max_size: max_batch_size,
              received: entries.size
            }, status: :payload_too_large
            return
          end

          # Create raw entries
          raw_entries = entries.map do |entry|
            {
              token_id: current_token.id,
              raw_payload: entry.to_json,
              received_at: Time.current,
              parsed: false
            }
          end

          # Bulk insert
          SolidLog.without_logging do
            SolidLog::RawEntry.insert_all(raw_entries)
          end

          render json: {
            status: "accepted",
            count: entries.size,
            message: "Log entries queued for processing"
          }, status: :accepted
        rescue JSON::ParserError => e
          render json: {
            error: "Invalid JSON",
            message: e.message
          }, status: :bad_request
        end

        private

        def max_batch_size
          SolidLog.configuration.max_batch_size
        end

        # Parse NDJSON (newline-delimited JSON) from request body
        def parse_ndjson_body
          return [] unless request.body

          body = request.body.read
          return [] if body.blank?

          # Check if it's NDJSON (multiple lines) or regular JSON
          if body.include?("\n")
            # NDJSON format
            body.lines.map do |line|
              JSON.parse(line.strip) unless line.strip.empty?
            end.compact
          else
            # Regular JSON (single entry or array)
            JSON.parse(body)
          end
        end
      end
    end
  end
end
