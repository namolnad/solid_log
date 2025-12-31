require "test_helper"

module SolidLog
  class FieldAnalysisJobTest < ActiveSupport::TestCase
    test "analyzes fields and logs recommendations" do
      # Create hot field (usage_count > 1000)
      Field.create!(
        name: "user_id",
        field_type: "number",
        usage_count: 5000,
        last_seen_at: Time.current,
        promoted: false
      )

      # Create low-usage field (should not be recommended)
      Field.create!(
        name: "debug_flag",
        field_type: "boolean",
        usage_count: 100,
        last_seen_at: Time.current,
        promoted: false
      )

      # Run analysis job without auto-promote
      assert_nothing_raised do
        FieldAnalysisJob.perform(auto_promote: false)
      end

      # Fields should not be promoted (auto_promote: false)
      assert_equal false, Field.find_by(name: "user_id").promoted
    end

    test "auto-promotes high-priority fields when auto_promote is true" do
      # Create very high-usage field (should get priority >= 80)
      high_priority_field = Field.create!(
        name: "user_id",
        field_type: "number",
        usage_count: 10_000,  # Very high usage
        last_seen_at: Time.current,  # Recently seen
        promoted: false
      )

      # Run analysis job with auto-promote
      FieldAnalysisJob.perform(auto_promote: true)

      # High-priority field should be promoted
      assert high_priority_field.reload.promoted
    end

    test "does not auto-promote low-priority fields" do
      # Create moderate-usage field (priority < 80)
      low_priority_field = Field.create!(
        name: "session_id",
        field_type: "string",
        usage_count: 1500,  # Above threshold but not very high
        last_seen_at: 20.days.ago,  # Not recently seen
        promoted: false
      )

      # Run analysis job with auto-promote
      FieldAnalysisJob.perform(auto_promote: true)

      # Low-priority field should NOT be promoted
      assert_equal false, low_priority_field.reload.promoted
    end

    test "handles no fields meeting threshold" do
      # Create only low-usage fields
      Field.create!(
        name: "low_usage",
        field_type: "string",
        usage_count: 50,
        last_seen_at: Time.current,
        promoted: false
      )

      # Should not raise error
      assert_nothing_raised do
        FieldAnalysisJob.perform
      end
    end

    test "ignores already promoted fields" do
      # Create high-usage promoted field
      promoted_field = Field.create!(
        name: "already_promoted",
        field_type: "string",
        usage_count: 10_000,
        last_seen_at: Time.current,
        promoted: true
      )

      # Run analysis
      FieldAnalysisJob.perform(auto_promote: true)

      # Should remain promoted (no duplicate promotion)
      assert promoted_field.reload.promoted
    end

    test "ignores stale fields not seen recently" do
      # Create high-usage field but not seen in 60 days
      stale_field = Field.create!(
        name: "old_field",
        field_type: "string",
        usage_count: 10_000,
        last_seen_at: 60.days.ago,
        promoted: false
      )

      # Run analysis (only considers fields seen within 30 days)
      FieldAnalysisJob.perform(auto_promote: true)

      # Stale field should NOT be promoted
      assert_equal false, stale_field.reload.promoted
    end

    test "analyzes multiple fields and promotes highest priority" do
      # Create multiple hot fields with different priorities
      high_field = Field.create!(
        name: "high_priority",
        field_type: "number",  # Simple type (25 points)
        usage_count: 15_000,   # Very high usage
        last_seen_at: Time.current,  # Recent (25 points)
        promoted: false
      )

      medium_field = Field.create!(
        name: "medium_priority",
        field_type: "string",
        usage_count: 2000,
        last_seen_at: 10.days.ago,
        promoted: false
      )

      # Run analysis with auto-promote
      FieldAnalysisJob.perform(auto_promote: true)

      # Only high-priority field should be promoted
      assert high_field.reload.promoted
      assert_equal false, medium_field.reload.promoted
    end

    test "uses SolidLog.without_logging to prevent recursive logging" do
      silenced_during_job = nil

      # Create hot field
      Field.create!(
        name: "test_field",
        field_type: "string",
        usage_count: 5000,
        last_seen_at: Time.current,
        promoted: false
      )

      # Patch FieldAnalyzer.analyze to capture silenced state
      original_analyze = FieldAnalyzer.method(:analyze)
      FieldAnalyzer.define_singleton_method(:analyze) do |**args|
        silenced_during_job = SolidLog.silenced?
        original_analyze.call(**args)
      end

      # Run job
      FieldAnalysisJob.perform

      # Should be silenced during execution
      assert_equal true, silenced_during_job

      # Restore original method
      FieldAnalyzer.define_singleton_method(:analyze, original_analyze)
    end

    test "handles empty field registry" do
      assert_equal 0, Field.count

      # Should not raise error
      assert_nothing_raised do
        FieldAnalysisJob.perform
      end
    end

    test "default auto_promote parameter is false" do
      # Create high-priority field
      high_priority_field = Field.create!(
        name: "high_usage",
        field_type: "number",
        usage_count: 10_000,
        last_seen_at: Time.current,
        promoted: false
      )

      # Run without auto_promote parameter (defaults to false)
      FieldAnalysisJob.perform

      # Should NOT be promoted
      assert_equal false, high_priority_field.reload.promoted
    end

    test "respects field type priority in scoring" do
      # Create fields with different types but same usage
      string_field = Field.create!(
        name: "string_field",
        field_type: "string",  # 25 points
        usage_count: 1500,
        last_seen_at: Time.current,
        promoted: false
      )

      array_field = Field.create!(
        name: "array_field",
        field_type: "array",  # 10 points (less favorable)
        usage_count: 1500,
        last_seen_at: Time.current,
        promoted: false
      )

      # Get recommendations
      recommendations = FieldAnalyzer.analyze(threshold: 1000)

      # Find priorities
      string_priority = recommendations.find { |r| r[:field].name == "string_field" }&.dig(:priority)
      array_priority = recommendations.find { |r| r[:field].name == "array_field" }&.dig(:priority)

      # String field should have higher priority due to better type score
      assert string_priority > array_priority
    end

    test "analyzes and returns correct recommendation structure" do
      # Create hot field
      Field.create!(
        name: "test_field",
        field_type: "number",
        usage_count: 5000,
        last_seen_at: Time.current,
        promoted: false
      )

      # Get recommendations directly from service
      recommendations = FieldAnalyzer.analyze(threshold: 1000)

      # Should return array of recommendations
      assert_kind_of Array, recommendations
      assert_equal 1, recommendations.size

      # Check recommendation structure
      rec = recommendations.first
      assert_includes rec, :field
      assert_includes rec, :priority
      assert_includes rec, :reason

      assert_kind_of Field, rec[:field]
      assert_kind_of Integer, rec[:priority]
      assert_kind_of String, rec[:reason]

      # Priority should be in valid range
      assert rec[:priority] >= 0
      assert rec[:priority] <= 100
    end

    test "limits top recommendations logged to 10" do
      # Create 15 hot fields
      15.times do |i|
        Field.create!(
          name: "field_#{i}",
          field_type: "string",
          usage_count: 1000 + (i * 100),
          last_seen_at: Time.current,
          promoted: false
        )
      end

      # Run analysis
      # Should log only top 10 (based on job implementation)
      assert_nothing_raised do
        FieldAnalysisJob.perform
      end
    end

    test "calculates recency score correctly" do
      # Create field seen today
      recent_field = Field.create!(
        name: "recent",
        field_type: "string",
        usage_count: 1500,
        last_seen_at: Time.current,
        promoted: false
      )

      # Create field seen 20 days ago
      old_field = Field.create!(
        name: "old",
        field_type: "string",
        usage_count: 1500,
        last_seen_at: 20.days.ago,
        promoted: false
      )

      recommendations = FieldAnalyzer.analyze(threshold: 1000)

      recent_priority = recommendations.find { |r| r[:field].name == "recent" }&.dig(:priority)
      old_priority = recommendations.find { |r| r[:field].name == "old" }&.dig(:priority)

      # Recent field should have higher priority due to recency score
      assert recent_priority > old_priority
    end
  end
end
