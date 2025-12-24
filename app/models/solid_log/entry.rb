module SolidLog
  class Entry < ApplicationRecord
    self.table_name = "solid_log_entries"

    belongs_to :raw_entry, foreign_key: :raw_id, optional: true

    validates :level, presence: true
    validates :created_at, presence: true

    LOG_LEVELS = %w[debug info warn error fatal unknown].freeze

    # Scopes for filtering
    scope :by_level, ->(level) { where(level: level) if level.present? }
    scope :by_app, ->(app) { where(app: app) if app.present? }
    scope :by_env, ->(env) { where(env: env) if env.present? }
    scope :by_request_id, ->(request_id) { where(request_id: request_id) if request_id.present? }
    scope :by_job_id, ->(job_id) { where(job_id: job_id) if job_id.present? }
    scope :by_time_range, ->(start_time, end_time) {
      scope = all
      scope = scope.where("created_at >= ?", start_time) if start_time.present?
      scope = scope.where("created_at <= ?", end_time) if end_time.present?
      scope
    }
    scope :recent, -> { order(created_at: :desc) }
    scope :errors, -> { where(level: %w[error fatal]) }

    # Full-text search (database-agnostic)
    def self.search_fts(query)
      return all if query.blank?

      adapter = SolidLog.adapter
      return all unless adapter.supports_full_text_search?

      # Use database-specific FTS implementation
      # SQLite FTS5: JOIN fts table and use MATCH
      sanitized_query = connection.quote(query)
      joins("JOIN solid_log_entries_fts ON solid_log_entries.id = solid_log_entries_fts.rowid")
        .where("solid_log_entries_fts MATCH #{sanitized_query}")
    rescue => e
      Rails.logger.error("Full-text search error: #{e.message}")
      all
    end

    # Filter by a dynamic field in extra_fields JSON (database-agnostic)
    def self.filter_by_field(field_name, field_value)
      return all if field_name.blank?

      adapter = SolidLog.adapter
      json_extract = adapter.extract_json_field('extra_fields', field_name)

      # SQLite json_extract returns values with their JSON types
      # For numeric values, we need to handle both string and number comparisons
      where("#{json_extract} = ? OR #{json_extract} = ?", field_value.to_s, field_value)
    rescue => e
      Rails.logger.error("Field filter error: #{e.message}")
      all
    end

    # Get correlation timeline for a request
    def self.correlation_timeline_for_request(request_id)
      by_request_id(request_id).recent
    end

    # Get correlation timeline for a job
    def self.correlation_timeline_for_job(job_id)
      by_job_id(job_id).recent
    end

    # Get available facets for a field
    def self.facets_for(field, limit: 100)
      case field
      when "level"
        distinct.pluck(:level).compact.sort
      when "app"
        distinct.pluck(:app).compact.sort
      when "env"
        distinct.pluck(:env).compact.sort
      when "controller"
        distinct.pluck(:controller).compact.take(limit).sort
      when "action"
        distinct.pluck(:action).compact.take(limit).sort
      when "method"
        distinct.pluck(:method).compact.sort
      else
        []
      end
    end

    # Parse extra_fields JSON
    def extra_fields_hash
      return {} if extra_fields.blank?
      @extra_fields_hash ||= JSON.parse(extra_fields)
    rescue JSON::ParserError
      {}
    end

    # Format log level with color class
    def level_badge_class
      case level
      when "debug"
        "badge-gray"
      when "info"
        "badge-blue"
      when "warn"
        "badge-yellow"
      when "error"
        "badge-red"
      when "fatal"
        "badge-dark-red"
      else
        "badge-gray"
      end
    end

    # Check if this entry has correlation data
    def correlated?
      request_id.present? || job_id.present?
    end

    # Prevent recursive logging
    around_save :without_logging_wrapper
    around_create :without_logging_wrapper
    around_update :without_logging_wrapper
    around_destroy :without_logging_wrapper

    def self.destroy_all
      SolidLog.without_logging { super }
    end

    def self.delete_all
      SolidLog.without_logging { super }
    end

    private

    def without_logging_wrapper
      SolidLog.without_logging { yield }
    end
  end
end
