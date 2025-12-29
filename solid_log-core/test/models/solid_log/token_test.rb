require "test_helper"

module SolidLog
  class TokenTest < ActiveSupport::TestCase
    test "generate! creates a token with hashed value" do
      result = Token.generate!("Test API")
      token = Token.find(result[:id])

      assert token.persisted?
      assert_equal "Test API", token.name
      assert token.token_hash.present?
      assert_equal 64, token.token_hash.length  # HMAC-SHA256 hex digest
      assert_match /^[a-f0-9]{64}$/, token.token_hash  # Hex string
    end

    test "generate! returns plaintext token only once" do
      result = Token.generate!("Test API")

      assert result.is_a?(Hash)
      assert result[:token].present?
      assert result[:token].start_with?("slk_")
      assert_equal "Test API", result[:name]
    end

    test "authenticate returns true for correct token" do
      result = Token.generate!("Test API")
      token = Token.find_by(name: "Test API")

      assert token.authenticate(result[:token])
    end

    test "authenticate returns false for incorrect token" do
      Token.generate!("Test API")
      token = Token.find_by(name: "Test API")

      assert_not token.authenticate("wrong_token")
    end

    test "touch_last_used! updates last_used_at" do
      token = Token.generate!("Test API")
      token = Token.find(token[:id])

      assert_nil token.last_used_at

      travel_to 1.hour.from_now do
        token.touch_last_used!
        assert_not_nil token.reload.last_used_at
        assert_in_delta Time.current, token.last_used_at, 1.second
      end
    end

    test "validates presence of name" do
      token = Token.new(token_hash: "hash")

      assert_not token.valid?
      assert_includes token.errors[:name], "can't be blank"
    end

    test "validates uniqueness of token_hash" do
      first_token = Token.generate!("First")
      first_token = Token.find(first_token[:id])

      duplicate_token = Token.new(
        name: "Second",
        token_hash: first_token.token_hash
      )

      assert_not duplicate_token.valid?
      assert_includes duplicate_token.errors[:token_hash], "has already been taken"
    end

    test "generated tokens are cryptographically secure" do
      tokens = 100.times.map { Token.generate!("Test #{_1}")[:token] }

      # All tokens should be unique
      assert_equal tokens.size, tokens.uniq.size

      # All tokens should be at least 32 characters
      assert tokens.all? { |t| t.length >= 32 }
    end
  end
end
