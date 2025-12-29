require "test_helper"

module SolidLog
  class FieldTest < ActiveSupport::TestCase
    test "track creates new field" do
      Field.track("user_id", 42)

      field = Field.find_by(name: "user_id")

      assert_not_nil field
      assert_equal "number", field.field_type
      assert_equal 1, field.usage_count
      assert_not_nil field.last_seen_at
    end

    test "track increments existing field usage" do
      Field.track("user_id", 42)
      initial_count = Field.find_by(name: "user_id").usage_count

      Field.track("user_id", 43)

      field = Field.find_by(name: "user_id")
      assert_equal initial_count + 1, field.usage_count
    end

    test "track infers string type" do
      Field.track("username", "john_doe")

      field = Field.find_by(name: "username")
      assert_equal "string", field.field_type
    end

    test "track infers number type" do
      Field.track("count", 42)

      field = Field.find_by(name: "count")
      assert_equal "number", field.field_type
    end

    test "track infers boolean type" do
      Field.track("is_admin", true)

      field = Field.find_by(name: "is_admin")
      assert_equal "boolean", field.field_type
    end

    test "track infers datetime type" do
      Field.track("logged_at", "2025-01-15T10:30:45Z")

      field = Field.find_by(name: "logged_at")
      assert_equal "datetime", field.field_type
    end

    test "increment_usage! increases count" do
      field = Field.create!(name: "test_field", field_type: "string", usage_count: 5)

      field.increment_usage!

      assert_equal 6, field.reload.usage_count
      assert field.last_seen_at >= 1.second.ago
    end

    test "promote! marks field as promoted" do
      field = Field.create!(name: "user_id", field_type: "number")

      assert_not field.promoted?

      field.promote!

      assert field.promoted?
    end

    test "demote! marks field as not promoted" do
      field = Field.create!(name: "user_id", field_type: "number", promoted: true)

      assert field.promoted?

      field.demote!

      assert_not field.promoted?
    end

    test "promotable? returns true for high usage" do
      field = Field.create!(name: "user_id", field_type: "number", usage_count: 2000)

      assert field.promotable?
    end

    test "promotable? returns false for low usage" do
      field = Field.create!(name: "user_id", field_type: "number", usage_count: 100)

      assert_not field.promotable?
    end

    test "promotable? returns false if already promoted" do
      field = Field.create!(
        name: "user_id",
        field_type: "number",
        usage_count: 2000,
        promoted: true
      )

      assert_not field.promotable?
    end

    test "validates uniqueness of name" do
      Field.create!(name: "user_id", field_type: "number")
      duplicate = Field.new(name: "user_id", field_type: "string")

      assert_not duplicate.valid?
      assert_includes duplicate.errors[:name], "has already been taken"
    end
  end
end
