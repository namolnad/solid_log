require "test_helper"

module SolidLog
  module UI
    class EntriesHelperTest < ActionView::TestCase
      test "pretty_json formats valid JSON" do
        json_string = '{"key":"value","nested":{"foo":"bar"}}'
        result = pretty_json(json_string)

        assert_includes result, "  "
        assert_includes result, "key"
        assert_includes result, "value"
      end

      test "pretty_json returns original string for invalid JSON" do
        invalid_json = "not valid json"
        result = pretty_json(invalid_json)
        assert_equal invalid_json, result
      end

      test "pretty_json returns empty string for blank input" do
        assert_equal "", pretty_json(nil)
        assert_equal "", pretty_json("")
      end
    end
  end
end
