require "test_helper"

module SolidLog
  module UI
    class FieldsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @routes = Engine.routes
        @field = create_field(name: "user_id", usage_count: 1500, promoted: true, filter_type: "tokens")
      end

      test "should get index" do
        get solid_log_ui.fields_path
        assert_response :success
      end

      test "should load fields ordered by usage" do
        # Create fields with different usage counts
        create_field(name: "field_1", usage_count: 100)
        create_field(name: "field_2", usage_count: 500)
        create_field(name: "field_3", usage_count: 200)

        get solid_log_ui.fields_path
        assert_response :success
        fields = assigns(:fields)
        assert fields.is_a?(ActiveRecord::Relation)
        # Verify ordering by usage_count descending
        counts = fields.pluck(:usage_count)
        assert_equal counts, counts.sort.reverse
      end

      test "should identify hot fields" do
        create_field(name: "hot_field_1", usage_count: 1500)
        create_field(name: "hot_field_2", usage_count: 2000)
        create_field(name: "cold_field", usage_count: 100)

        get solid_log_ui.fields_path
        assert_response :success
        hot_fields = assigns(:hot_fields)
        assert hot_fields.all? { |f| f.usage_count >= 1000 }
      end

      test "should promote field" do
        unpromoted_field = create_field(name: "session_id", promoted: false)
        assert_not unpromoted_field.promoted?

        post solid_log_ui.promote_field_path(unpromoted_field)
        assert_redirected_to solid_log_ui.fields_path

        unpromoted_field.reload
        assert unpromoted_field.promoted?
      end

      test "should demote field" do
        promoted_field = create_field(name: "promoted_user_id", promoted: true)
        assert promoted_field.promoted?

        post solid_log_ui.demote_field_path(promoted_field)
        assert_redirected_to solid_log_ui.fields_path

        promoted_field.reload
        assert_not promoted_field.promoted?
      end

      test "should update filter type" do
        patch solid_log_ui.update_filter_type_field_path(@field), params: {
          field: { filter_type: "multiselect" }
        }
        assert_redirected_to solid_log_ui.fields_path

        @field.reload
        assert_equal "multiselect", @field.filter_type
      end

      test "should not update with invalid filter type" do
        original_type = @field.filter_type

        patch solid_log_ui.update_filter_type_field_path(@field), params: {
          field: { filter_type: "invalid_type" }
        }
        assert_redirected_to solid_log_ui.fields_path

        @field.reload
        assert_equal original_type, @field.filter_type
      end

      test "should destroy field" do
        field_to_delete = create_field(name: "session_id")

        assert_difference("SolidLog::Field.count", -1) do
          delete solid_log_ui.field_path(field_to_delete)
        end

        assert_redirected_to solid_log_ui.fields_path
      end
    end
  end
end
