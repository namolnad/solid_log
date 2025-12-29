module SolidLog
  module UI
    # Dynamically inherit from configured base controller
    base_controller_class = begin
      SolidLog::UI.configuration.base_controller.constantize
    rescue NameError
      # Fallback to ActionController::Base if configuration not set or class doesn't exist
      ActionController::Base
    end

    class BaseController < base_controller_class
      include Turbo::Streams::TurboStreamsTagBuilder
      helper Turbo::Engine.helpers
      helper Importmap::ImportmapTagsHelper

      # Explicitly include engine helpers (now that they're in correct namespace path)
      helper SolidLog::UI::ApplicationHelper
      helper SolidLog::UI::DashboardHelper
      helper SolidLog::UI::EntriesHelper
      helper SolidLog::UI::TimelineHelper

      layout "solid_log/ui/application"

      before_action :authenticate_user!
      before_action :set_data_source

      # Override this method in your host application to implement custom authentication
      #
      # Example configurations in config/initializers/solid_log_ui.rb:
      #
      # 1. Using a Proc/Lambda:
      #   SolidLog::UI.configure do |config|
      #     config.authentication_method = ->(controller) {
      #       controller.redirect_to controller.root_path unless controller.current_user&.admin?
      #     }
      #   end
      #
      # 2. Using a method name:
      #   SolidLog::UI.configure do |config|
      #     config.authentication_method = :require_admin
      #   end
      #
      #   class ApplicationController
      #     def require_admin
      #       redirect_to root_path unless current_user&.admin?
      #     end
      #   end
      #
      # 3. Using basic auth:
      #   SolidLog::UI.configure do |config|
      #     config.authentication_method = :basic
      #   end
      #
      def authenticate_user!
        config = SolidLog::UI.configuration
        auth_method = config.authentication_method

        case auth_method
        when :none
          # No authentication required
          true
        when :basic
          authenticate_or_request_with_http_basic("SolidLog") do |username, password|
            authenticate_with_basic_auth(username, password)
          end
        when Proc
          # Call the proc in the controller's context
          instance_exec(&auth_method)
        when Symbol
          # Call the named method on the controller
          if respond_to?(auth_method, true)
            send(auth_method)
          else
            raise NoMethodError, "Authentication method '#{auth_method}' not defined. Define it in your ApplicationController or BaseController."
          end
        else
          render plain: "Invalid authentication configuration", status: :unauthorized
          false
        end
      end

      protected

      # Override this in host app to customize basic auth credentials
      def authenticate_with_basic_auth(username, password)
        # Default: check Rails credentials
        credentials = Rails.application.credentials.solidlog || {}
        username == credentials[:username] && password == credentials[:password]
      end

      # Helper to check if user is authenticated
      def authenticated?
        auth_method = SolidLog::UI.configuration.authentication_method

        case auth_method
        when :none
          true
        when :basic
          request.authorization.present?
        when Proc, Symbol
          # For custom auth (proc or method name), assume authenticated if we got this far
          # (since authenticate_user! would have redirected/rendered if not authenticated)
          true
        else
          false
        end
      end

      # Current user - override in host app if using custom auth
      def current_user
        nil
      end
      helper_method :current_user

      private

      def set_data_source
        @data_source = SolidLog::UI::DataSource.new
      end
    end
  end
end
