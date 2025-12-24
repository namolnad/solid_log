module SolidLog
  class TokensController < ApplicationController
    def index
      @tokens = SolidLog.without_logging do
        Token.order(created_at: :desc)
      end
    end

    def new
      @token = Token.new
    end

    def create
      @token = SolidLog.without_logging do
        Token.generate!(token_params[:name])
      end

      # Store plaintext token in flash for one-time display
      flash[:token_plaintext] = @token.plaintext_token
      redirect_to tokens_path, notice: "Token created successfully"
    rescue ActiveRecord::RecordInvalid => e
      @token = Token.new(token_params)
      flash.now[:alert] = "Failed to create token: #{e.message}"
      render :new, status: :unprocessable_entity
    end

    def destroy
      @token = Token.find(params[:id])
      token_name = @token.name

      SolidLog.without_logging do
        @token.destroy
      end

      redirect_to tokens_path, notice: "Token '#{token_name}' revoked"
    end

    private

    def token_params
      params.require(:token).permit(:name)
    end
  end
end
