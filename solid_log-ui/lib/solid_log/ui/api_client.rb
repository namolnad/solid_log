require 'net/http'
require 'json'
require 'uri'

module SolidLog
  module UI
    class ApiClient
      attr_reader :base_url, :token

      def initialize(base_url: nil, token: nil)
        @base_url = base_url || SolidLog::UI.configuration.service_url
        @token = token || SolidLog::UI.configuration.service_token

        raise ArgumentError, "base_url required for API client" if @base_url.blank?
        raise ArgumentError, "token required for API client" if @token.blank?
      end

      # GET /api/v1/entries
      def entries(params = {})
        get('/api/v1/entries', params)
      end

      # GET /api/v1/entries/:id
      def entry(id)
        get("/api/v1/entries/#{id}")
      end

      # POST /api/v1/search
      def search(query, params = {})
        post('/api/v1/search', { q: query }.merge(params))
      end

      # GET /api/v1/facets
      def facets(field)
        get('/api/v1/facets', { field: field })
      end

      # GET /api/v1/facets/all
      def all_facets
        get('/api/v1/facets/all')
      end

      # GET /api/v1/timelines/request/:request_id
      def request_timeline(request_id)
        get("/api/v1/timelines/request/#{request_id}")
      end

      # GET /api/v1/timelines/job/:job_id
      def job_timeline(job_id)
        get("/api/v1/timelines/job/#{job_id}")
      end

      # GET /api/v1/health
      def health
        get('/api/v1/health')
      end

      private

      def get(path, params = {})
        uri = URI.parse("#{@base_url}#{path}")
        uri.query = URI.encode_www_form(params) if params.any?

        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "Bearer #{@token}"
        request['Content-Type'] = 'application/json'

        perform_request(uri, request)
      end

      def post(path, body = {})
        uri = URI.parse("#{@base_url}#{path}")

        request = Net::HTTP::Post.new(uri)
        request['Authorization'] = "Bearer #{@token}"
        request['Content-Type'] = 'application/json'
        request.body = JSON.generate(body)

        perform_request(uri, request)
      end

      def perform_request(uri, request)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.open_timeout = 5
        http.read_timeout = 30

        response = http.request(request)

        case response.code.to_i
        when 200..299
          JSON.parse(response.body)
        when 404
          raise NotFoundError, "Resource not found: #{uri.path}"
        when 401
          raise AuthenticationError, "Authentication failed. Check your service_token."
        when 500..599
          raise ServerError, "Server error (#{response.code}): #{response.body}"
        else
          raise RequestError, "Request failed (#{response.code}): #{response.body}"
        end
      rescue JSON::ParserError => e
        raise ParseError, "Failed to parse JSON response: #{e.message}"
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
        raise ConnectionError, "Cannot connect to service at #{@base_url}: #{e.message}"
      end

      # Custom errors
      class RequestError < StandardError; end
      class NotFoundError < RequestError; end
      class AuthenticationError < RequestError; end
      class ServerError < RequestError; end
      class ConnectionError < RequestError; end
      class ParseError < RequestError; end
    end
  end
end
