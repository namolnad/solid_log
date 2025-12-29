require "net/http"
require "json"
require "uri"

module SolidLog
  module Core
    class HttpSender
      def initialize(url:, token:, retry_handler:)
        @url = url
        @token = token
        @retry_handler = retry_handler
      end

      # Send a batch of entries to the ingestion endpoint
      def send_batch(entries)
        return if entries.empty?

        @retry_handler.with_retry do
          perform_request(entries)
        end
      end

      private

      def perform_request(entries)
        uri = URI.parse(@url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = 5
        http.read_timeout = 10

        request = build_request(uri.path, entries)
        response = http.request(request)

        handle_response(response, entries)
      end

      def build_request(path, entries)
        request = Net::HTTP::Post.new(path)
        request["Authorization"] = "Bearer #{@token}"
        request["Content-Type"] = if entries.size == 1
                                    "application/json"
        else
                                    "application/x-ndjson"
        end

        request.body = if entries.size == 1
                        JSON.generate(entries.first)
        else
                        entries.map { |e| JSON.generate(e) }.join("\n")
        end

        request
      end

      def handle_response(response, entries)
        case response.code.to_i
        when 200..299
          # Success
          log_debug "Successfully sent #{entries.size} entries"
        when 400..499
          # Client error - don't retry
          log_error "Client error (#{response.code}): #{response.body}"
          raise ClientError, "HTTP #{response.code}: #{response.body}"
        when 500..599
          # Server error - retry
          log_error "Server error (#{response.code}): #{response.body}"
          raise ServerError, "HTTP #{response.code}: #{response.body}"
        else
          log_error "Unexpected response (#{response.code}): #{response.body}"
          raise UnexpectedError, "HTTP #{response.code}: #{response.body}"
        end
      end

      def log_debug(message)
        Rails.logger.debug "SolidLog::Client: #{message}" if defined?(Rails)
      end

      def log_error(message)
        Rails.logger.error "SolidLog::Client: #{message}" if defined?(Rails)
      end

      # Error classes
      class ClientError < StandardError; end
      class ServerError < StandardError; end
      class UnexpectedError < StandardError; end
    end
  end
end
