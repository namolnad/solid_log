module SolidLog
  class Field < ApplicationRecord
    self.table_name = "solid_log_fields"

    FIELD_TYPES = %w[string number boolean datetime array object].freeze
    FILTER_TYPES = %w[multiselect range exact contains tokens].freeze

    # High-cardinality fields that should default to tokens
    HIGH_CARDINALITY_PATTERNS = %w[user_id session_id ip_address uuid transaction_id].freeze

    validates :name, presence: true, uniqueness: true
    validates :field_type, presence: true, inclusion: { in: FIELD_TYPES }
    validates :filter_type, presence: true, inclusion: { in: FILTER_TYPES }
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
      field.filter_type ||= infer_filter_type(field.field_type, name)

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

    # Infer filter type from field type and name
    def self.infer_filter_type(field_type, field_name = nil)
      # Check if field name suggests high cardinality
      if field_name && HIGH_CARDINALITY_PATTERNS.any? { |pattern| field_name.to_s.include?(pattern) }
        return "tokens"
      end

      case field_type
      when "number", "datetime"
        "range"
      when "boolean"
        "exact"
      else
        "multiselect"
      end
    end
  end
end
