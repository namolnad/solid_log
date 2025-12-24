module SolidLog
  module Api
    class BaseController < ActionController::API
      before_action :authenticate_token!

      rescue_from ActionDispatch::Http::Parameters::ParseError do |exception|
        render json: {
          error: "Invalid JSON",
          message: exception.message
        }, status: :unprocessable_entity
      end

      rescue_from ActionController::BadRequest do |exception|
        render json: {
          error: "Invalid JSON",
          message: exception.message
        }, status: :unprocessable_entity
      end

      rescue_from StandardError do |exception|
        # Check if it's a parameter parsing error based on message
        if exception.message.include?("parsing request parameters")
          render json: {
            error: "Invalid JSON",
            message: exception.message
          }, status: :unprocessable_entity
        else
          Rails.logger.error "SolidLog API Error: #{exception.message}"
          Rails.logger.error exception.backtrace.join("\n")

          render json: {
            error: "Internal server error",
            message: exception.message
          }, status: :internal_server_error
        end
      end

      rescue_from ActiveRecord::RecordInvalid do |exception|
        render json: {
          error: "Validation error",
          details: exception.record.errors.full_messages
        }, status: :unprocessable_entity
      end

      private

      def authenticate_token!
        token_value = extract_bearer_token

        unless token_value
          render json: { error: "Missing or invalid Authorization header" }, status: :unauthorized
          return
        end

        @current_token = SolidLog::Token.authenticate(token_value)

        unless @current_token
          render json: { error: "Invalid token" }, status: :unauthorized
          return
        end

        # Touch last_used_at timestamp
        @current_token.touch_last_used!
      end

      def current_token
        @current_token
      end

      def extract_bearer_token
        header = request.headers["Authorization"]
        return nil unless header

        # Expected format: "Bearer <token>"
        matches = header.match(/^Bearer (.+)$/i)
        matches[1] if matches
      end
    end
  end
end
