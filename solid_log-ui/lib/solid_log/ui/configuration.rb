module SolidLog
  module UI
    class Configuration
      attr_accessor :mode,
                    :service_url,
                    :service_token,
                    :database_path,
                    :websocket_enabled,
                    :stream_view_style,
                    :facet_cache_ttl,
                    :per_page,
                    :base_controller
      attr_reader :authentication_method

      def initialize
        # Mode: :direct_db (same database) or :http_api (remote service)
        @mode = :direct_db

        # HTTP API mode settings
        @service_url = nil
        @service_token = nil

        # Direct DB mode settings
        @database_path = nil

        # Controller inheritance - defaults to ActionController::Base
        # Set to "ApplicationController" or your app's base controller
        @base_controller = "ActionController::Base"

        # UI settings
        # Authentication: :none, :basic, or a Proc/Symbol/String
        # - :none - no authentication required
        # - :basic - HTTP basic authentication (uses authenticate_with_basic_auth)
        # - Proc/Lambda - custom authentication logic (called in controller context)
        # - Symbol/String - method name to call on the controller
        @authentication_method = :none
        @websocket_enabled = true
        @stream_view_style = :compact  # :compact or :expanded
        @facet_cache_ttl = 1.minute
        @per_page = 100
      end

      # Set authentication method with validation
      def authentication_method=(value)
        case value
        when :none, :basic
          @authentication_method = value
        when Proc
          @authentication_method = value
        when Symbol, String
          @authentication_method = value.to_sym
        else
          raise ArgumentError, "authentication_method must be :none, :basic, a Proc, or a Symbol/String method name"
        end
      end

      # Check if authentication is a proc
      def authentication_proc?
        authentication_method.is_a?(Proc)
      end

      # Check if authentication is a method name
      def authentication_method_name?
        authentication_method.is_a?(Symbol) && ![:none, :basic].include?(authentication_method)
      end

      # Validate configuration
      def valid?
        errors = []

        case mode
        when :direct_db
          # Direct DB mode doesn't require additional config (uses core's connection)
        when :http_api
          errors << "service_url required for http_api mode" if service_url.blank?
          errors << "service_token required for http_api mode" if service_token.blank?
        else
          errors << "mode must be :direct_db or :http_api"
        end

        # Authentication validation is handled by the setter

        if errors.any?
          raise ArgumentError, "Invalid UI configuration:\n  #{errors.join("\n  ")}"
        end

        true
      end

      def direct_db_mode?
        mode == :direct_db
      end

      def http_api_mode?
        mode == :http_api
      end
    end
  end
end
