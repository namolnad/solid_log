module SolidLog
  class Field < ApplicationRecord
    self.table_name = "solid_log_fields"

    FIELD_TYPES = %w[string number boolean datetime array object].freeze

    validates :name, presence: true, uniqueness: true
    validates :field_type, presence: true, inclusion: { in: FIELD_TYPES }
    validates :usage_count, numericality: { greater_than_or_equal_to: 0 }

    scope :hot_fields, ->(threshold = 1000) { where("usage_count >= ?", threshold).order(usage_count: :desc) }
    scope :promoted, -> { where(promoted: true) }
    scope :unpromoted, -> { where(promoted: false) }
    scope :recently_seen, ->(days = 7) { where("last_seen_at >= ?", days.days.ago) }

    # Increment usage count and update last_seen_at
    def increment_usage!
      increment!(:usage_count)
      touch(:last_seen_at)
    end

    # Mark field as promoted (has its own column)
    def promote!
      update!(promoted: true)
    end

    # Mark field as unpromoted (stored in JSON)
    def demote!
      update!(promoted: false)
    end

    # Check if field is promotable (high usage and not already promoted)
    def promotable?(threshold: 1000)
      !promoted? && usage_count >= threshold
    end

    # Track a field occurrence
    def self.track(name, value)
      field = find_or_initialize_by(name: name)
      field.field_type ||= infer_type(value)

      # Save if new record before calling increment_usage!
      field.save! if field.new_record?

      field.increment_usage!
      field
    end

    private

    # Infer field type from value
    def self.infer_type(value)
      case value
      when Time, DateTime, Date
        "datetime"
      when TrueClass, FalseClass
        "boolean"
      when Numeric
        "number"
      when Array
        "array"
      when Hash
        "object"
      when String
        # Try to parse as datetime
        begin
          Time.parse(value)
          "datetime"
        rescue ArgumentError
          "string"
        end
      else
        "string"
      end
    end
  end
end
