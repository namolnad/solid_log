require "test_helper"

module SolidLog
  class DatabaseConstraintsTest < ActiveSupport::TestCase
    # Test unique constraints
    test "prevents duplicate token hashes" do
      token1 = Token.generate!("Token 1")
      token_model = Token.find(token1[:id])

      # Try to create another token with same hash
      token2 = Token.new(name: "Token 2", token_hash: token_model.token_hash)

      assert_not token2.save
      assert_includes token2.errors[:token_hash], "has already been taken"
    end

    test "prevents duplicate field names" do
      Field.create!(name: "user_id", field_type: "string")

      # Try to create another field with same name
      duplicate_field = Field.new(name: "user_id", field_type: "string")

      assert_not duplicate_field.save
      assert_includes duplicate_field.errors[:name], "has already been taken"
    end

    test "prevents duplicate facet cache keys" do
      FacetCache.create!(
        key_name: "levels",
        cache_value: ["info", "error"].to_json
      )

      # Try to create another cache with same key
      duplicate_cache = FacetCache.new(
        key_name: "levels",
        cache_value: ["warn"].to_json
      )

      assert_not duplicate_cache.save
      assert_includes duplicate_cache.errors[:key_name], "has already been taken"
    end

    # Test not null constraints
    test "requires token name" do
      token_result = nil

      # Temporarily allow save to fail
      assert_raises(ActiveRecord::RecordInvalid) do
        SolidLog.without_logging do
          token = Token.new(name: nil, token_hash: "test_hash")
          token.save!
        end
      end
    end

    test "requires entry level" do
      raw_entry = RawEntry.create!(
        payload: {message: "test"}.to_json,
        token_id: create_test_token[:id]
      )

      assert_raises(ActiveRecord::RecordInvalid) do
        Entry.create!(
          raw_id: raw_entry.id,
          timestamp: Time.current,
          created_at: Time.current,
          level: nil  # Should fail
        )
      end
    end

    test "requires entry timestamp" do
      raw_entry = RawEntry.create!(
        payload: {message: "test"}.to_json,
        token_id: create_test_token[:id]
      )

      assert_raises(ActiveRecord::RecordInvalid) do
        Entry.create!(
          raw_id: raw_entry.id,
          timestamp: nil,  # Should fail
          created_at: Time.current,
          level: "info"
        )
      end
    end

    test "requires raw_entry payload" do
      token = create_test_token

      assert_raises(ActiveRecord::RecordInvalid) do
        RawEntry.create!(
          payload: nil,  # Should fail
          token_id: token[:id]
        )
      end
    end

    # Test data references
    test "entry can be created with any raw_id" do
      # Note: No foreign key constraint on raw_id, so this should succeed
      # This is by design for performance reasons
      entry = Entry.create!(
        raw_id: 999999,  # Non-existent, but allowed
        timestamp: Time.current,
        created_at: Time.current,
        level: "info",
        message: "test"
      )

      assert_equal 999999, entry.raw_id
    end


    # Test data integrity
    test "prevents saving entry without created_at" do
      raw_entry = RawEntry.create!(
        payload: {message: "test"}.to_json,
        token_id: create_test_token[:id]
      )

      assert_raises(ActiveRecord::RecordInvalid) do
        Entry.create!(
          raw_id: raw_entry.id,
          timestamp: Time.current,
          created_at: nil,  # Should fail
          level: "info"
        )
      end
    end

    test "allows entry with nil extra_fields" do
      raw_entry = RawEntry.create!(
        payload: {message: "test"}.to_json,
        token_id: create_test_token[:id]
      )

      # Should succeed - extra_fields is nullable
      entry = Entry.create!(
        raw_id: raw_entry.id,
        timestamp: Time.current,
        created_at: Time.current,
        level: "info",
        message: "test",
        extra_fields: nil
      )

      assert_nil entry.extra_fields
    end

    test "allows multiple entries with nil request_id" do
      token = create_test_token
      raw1 = RawEntry.create!(payload: {message: "test1"}.to_json, token_id: token[:id])
      raw2 = RawEntry.create!(payload: {message: "test2"}.to_json, token_id: token[:id])

      # Both should succeed even with nil request_id (not a unique constraint)
      entry1 = Entry.create!(
        raw_id: raw1.id,
        timestamp: Time.current,
        created_at: Time.current,
        level: "info",
        request_id: nil
      )

      entry2 = Entry.create!(
        raw_id: raw2.id,
        timestamp: Time.current,
        created_at: Time.current,
        level: "info",
        request_id: nil
      )

      assert_nil entry1.request_id
      assert_nil entry2.request_id
    end

    # Test that unique constraints work
    test "ensures token hashes are cryptographically unique" do
      # Generate multiple tokens and verify all have unique hashes
      token_ids = []
      5.times do |i|
        SolidLog.without_logging do
          token = Token.generate!("Token #{i}")
          token_ids << token[:id]
        end
      end

      # All tokens should have unique hashes
      hashes = Token.where(id: token_ids).pluck(:token_hash)
      assert_equal 5, hashes.size
      assert_equal 5, hashes.uniq.size, "All tokens should have unique hashes"
    end
  end
end
