require "test_helper"

module SolidLog
  module UI
    class TokensControllerTest < ActionDispatch::IntegrationTest
      setup do
        @routes = Engine.routes
        @token = create_test_token(name: "Production Token")[:model]
      end

      test "should get index" do
        get solid_log_ui.tokens_path
        assert_response :success
        assert assigns(:tokens).is_a?(ActiveRecord::Relation)
      end

      test "should show tokens ordered by created_at desc" do
        # Create tokens with different timestamps
        token1 = create_test_token(name: "Token 1")[:model]
        token2 = create_test_token(name: "Token 2")[:model]
        # Update timestamps to ensure ordering
        token1.update_column(:created_at, 2.days.ago)
        token2.update_column(:created_at, 1.day.ago)

        get solid_log_ui.tokens_path
        assert_response :success
        tokens = assigns(:tokens)
        created_ats = tokens.pluck(:created_at)
        assert_equal created_ats, created_ats.sort.reverse
      end

      test "should get new" do
        get solid_log_ui.new_token_path
        assert_response :success
        assert assigns(:token).new_record?
      end

      test "should create token" do
        assert_difference("SolidLog::Token.count", 1) do
          post solid_log_ui.tokens_path, params: {
            token: { name: "New Test Token" }
          }
        end

        assert_redirected_to solid_log_ui.tokens_path
        assert_not_nil flash[:token_plaintext]
        assert_match /created successfully/, flash[:notice]
      end

      test "should generate valid authentication token" do
        post solid_log_ui.tokens_path, params: {
          token: { name: "API Token" }
        }

        plaintext_token = flash[:token_plaintext]
        assert_not_nil plaintext_token

        # Verify token format (should be "slk_" + 32 bytes hex = 68 characters)
        assert_equal 68, plaintext_token.length
        assert_match /^slk_[a-f0-9]{64}$/, plaintext_token

        # Verify the token can authenticate successfully
        created_token = SolidLog::Token.last
        assert created_token.authenticate(plaintext_token)

        # Verify wrong token fails authentication
        assert_not created_token.authenticate("wrong_token_12345")
        assert_not created_token.authenticate("slk_" + "0" * 64)
      end

      test "should show plaintext token only once" do
        # Create token and get plaintext
        post solid_log_ui.tokens_path, params: {
          token: { name: "One-Time Token" }
        }
        plaintext = flash[:token_plaintext]

        # Reload the model - plaintext should not be accessible
        created_token = SolidLog::Token.last
        assert_not_equal plaintext, created_token.token_hash

        # Token hash should be HMAC-SHA256 (64 hex characters)
        assert_equal 64, created_token.token_hash.length
        assert_match /^[a-f0-9]{64}$/, created_token.token_hash
      end

      test "should not create token with invalid params" do
        assert_no_difference("SolidLog::Token.count") do
          post solid_log_ui.tokens_path, params: {
            token: { name: "" }
          }
        end

        assert_response :unprocessable_entity
        assert_match /Failed to create token/, flash[:alert]
      end

      test "should destroy token" do
        token_to_delete = create_test_token(name: "Staging Token")[:model]

        assert_difference("SolidLog::Token.count", -1) do
          delete solid_log_ui.token_path(token_to_delete)
        end

        assert_redirected_to solid_log_ui.tokens_path
        assert_match /revoked/, flash[:notice]
      end
    end
  end
end
