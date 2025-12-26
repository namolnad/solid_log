require "test_helper"

module SolidLog
  class RawEntryTest < ActiveSupport::TestCase
    setup do
      @token = create_test_token
    end

    test "creates raw entry with valid attributes" do
      raw_entry = RawEntry.create!(
        payload: { level: "info", message: "test" }.to_json,
        token_id: @token[:id],
        received_at: Time.current
      )

      assert raw_entry.persisted?
      assert_not raw_entry.parsed?
      assert_nil raw_entry.parsed_at
    end

    test "validates presence of payload" do
      raw_entry = RawEntry.new(token_id: @token[:id])

      assert_not raw_entry.valid?
      assert_includes raw_entry.errors[:payload], "can't be blank"
    end

    test "unparsed scope returns only unparsed entries" do
      parsed = create_raw_entry(token: @token)
      parsed.update!(parsed: true)

      unparsed = create_raw_entry(token: @token)

      assert_equal [ unparsed ], RawEntry.unparsed.to_a
    end

    test "parsed scope returns only parsed entries" do
      parsed = create_raw_entry(token: @token)
      parsed.update!(parsed: true)

      create_raw_entry(token: @token)

      assert_equal [ parsed ], RawEntry.parsed.to_a
    end

    test "stale_unparsed returns entries older than threshold" do
      old_entry = create_raw_entry(token: @token)
      old_entry.update!(received_at: 2.hours.ago)

      recent_entry = create_raw_entry(token: @token)

      stale = RawEntry.stale_unparsed(1.hour.ago)

      assert_includes stale, old_entry
      assert_not_includes stale, recent_entry
    end

    test "mark_parsed! updates parsed status" do
      raw_entry = create_raw_entry(token: @token)

      assert_not raw_entry.parsed?

      raw_entry.mark_parsed!

      assert raw_entry.parsed?
      assert_not_nil raw_entry.parsed_at
    end

    test "payload_hash returns parsed JSON" do
      payload = { level: "info", message: "test", user_id: 42 }
      raw_entry = create_raw_entry(payload: payload, token: @token)

      assert_equal payload.stringify_keys, raw_entry.payload_hash
    end

    test "payload_hash returns empty hash for invalid JSON" do
      raw_entry = RawEntry.create!(
        payload: "{invalid json",
        token_id: @token[:id],
        received_at: Time.current
      )

      assert_equal({}, raw_entry.payload_hash)
    end

    test "claim_batch returns unparsed entries" do
      entries = 5.times.map { create_raw_entry(token: @token) }

      claimed = RawEntry.claim_batch(batch_size: 3)

      assert_equal 3, claimed.size
      assert claimed.all?(&:persisted?)
    end

    test "claim_batch marks entries as parsed" do
      3.times { create_raw_entry(token: @token) }

      claimed_ids = RawEntry.claim_batch(batch_size: 3).map(&:id)

      claimed_ids.each do |id|
        assert RawEntry.find(id).parsed?
      end
    end

    test "claim_batch returns empty array when no unparsed entries" do
      claimed = RawEntry.claim_batch(batch_size: 10)

      assert_equal [], claimed
    end

    test "claim_batch respects batch size" do
      10.times { create_raw_entry(token: @token) }

      claimed = RawEntry.claim_batch(batch_size: 3)

      assert_equal 3, claimed.size
    end

    test "claim_batch is thread-safe and prevents duplicate claims" do
      # Create 20 entries for claiming
      20.times { create_raw_entry(token: @token) }

      claimed_ids = Concurrent::Set.new
      threads = []

      # 5 threads each trying to claim 5 entries (25 total attempts for 20 entries)
      5.times do
        threads << Thread.new do
          batch = RawEntry.claim_batch(batch_size: 5)
          batch.each { |entry| claimed_ids.add(entry.id) }
        end
      end

      threads.each(&:join)

      # Verify no duplicates: exactly 20 unique entries claimed
      assert_equal 20, claimed_ids.size, "Each entry should be claimed exactly once"

      # Verify all entries are marked as parsed
      assert_equal 0, RawEntry.unparsed.count, "All entries should be marked as parsed"
      assert_equal 20, RawEntry.parsed.count
    end
  end
end
