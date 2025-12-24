module SolidLog
  class Entry < ApplicationRecord
    self.table_name = "solid_log_entries"

    belongs_to :raw_entry, foreign_key: :raw_id, optional: true

    validates :level, presence: true
    validates :created_at, presence: true

    LOG_LEVELS = %w[debug info warn error fatal unknown].freeze

    # Scopes for filtering (support both single values and arrays for multi-select)
    scope :by_level, ->(level) { where(level: level) if level.present? }
    scope :by_app, ->(app) {
      return all if app.blank?
      app.is_a?(Array) ? where(app: app.reject(&:blank?)) : where(app: app)
    }
    scope :by_env, ->(env) {
      return all if env.blank?
      env.is_a?(Array) ? where(env: env.reject(&:blank?)) : where(env: env)
    }
    scope :by_controller, ->(controller) {
      return all if controller.blank?
      controller.is_a?(Array) ? where(controller: controller.reject(&:blank?)) : where(controller: controller)
    }
    scope :by_action, ->(action) {
      return all if action.blank?
      action.is_a?(Array) ? where(action: action.reject(&:blank?)) : where(action: action)
    }
    scope :by_path, ->(path) {
      return all if path.blank?
      path.is_a?(Array) ? where(path: path.reject(&:blank?)) : where(path: path)
    }
    scope :by_method, ->(method) {
      return all if method.blank?
      method.is_a?(Array) ? where(method: method.reject(&:blank?)) : where(method: method)
    }
    scope :by_status_code, ->(status_code) {
      return all if status_code.blank?
      status_code.is_a?(Array) ? where(status_code: status_code.reject(&:blank?)) : where(status_code: status_code)
    }
    scope :by_request_id, ->(request_id) { where(request_id: request_id) if request_id.present? }
    scope :by_job_id, ->(job_id) { where(job_id: job_id) if job_id.present? }
    scope :by_time_range, ->(start_time, end_time) {
      scope = all
      scope = scope.where("created_at >= ?", start_time) if start_time.present?
      scope = scope.where("created_at <= ?", end_time) if end_time.present?
      scope
    }
    scope :by_duration_range, ->(min_duration, max_duration) {
      scope = all
      scope = scope.where("duration >= ?", min_duration) if min_duration.present?
      scope = scope.where("duration <= ?", max_duration) if max_duration.present?
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
      return [] unless column_names.include?(field.to_s)

      # Get distinct values
      values = distinct.pluck(field).compact

      # Sort and limit
      case field.to_s
      when "level"
        # Sort by severity
        values.sort_by { |l| LOG_LEVELS.index(l) || 999 }
      when "status_code"
        # Sort numerically
        values.sort
      when "controller", "action", "path"
        # Limit and sort these potentially large lists
        values.take(limit).sort
      else
        # Default: sort alphabetically
        values.sort
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
