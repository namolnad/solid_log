module SolidLog
  class FieldsController < ApplicationController
    def index
      @fields = SolidLog.without_logging do
        Field.order(usage_count: :desc)
      end

      @hot_fields = @fields.select { |f| f.usage_count >= 1000 }
      @total_fields = @fields.size
    end

    def promote
      @field = Field.find(params[:id])

      SolidLog.without_logging do
        @field.promote!
      end

      redirect_to fields_path, notice: "Field '#{@field.name}' marked as promoted"
    end

    def demote
      @field = Field.find(params[:id])

      SolidLog.without_logging do
        @field.demote!
      end

      redirect_to fields_path, notice: "Field '#{@field.name}' marked as unpromoted"
    end

    def destroy
      @field = Field.find(params[:id])
      field_name = @field.name

      SolidLog.without_logging do
        @field.destroy
      end

      redirect_to fields_path, notice: "Field '#{field_name}' removed from registry"
    end
  end
end
