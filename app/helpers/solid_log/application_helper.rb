module SolidLog
  module ApplicationHelper
    # Navigation helpers
    def nav_link_class(path)
      base_class = "nav-link"
      current_path = request.path

      # Check if we're on this path or a sub-path
      active = if path == solid_log_path
        current_path == path || current_path == dashboard_path
      else
        current_path.start_with?(path)
      end

      active ? "#{base_class} active" : base_class
    end

    # Log display helpers (shared across views)
    def level_badge(level)
      badge_class = case level.to_s.downcase
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
        "badge-secondary"
      end

      content_tag(:span, level.upcase, class: "badge #{badge_class}")
    end

    def http_status_badge(status_code)
      return "" if status_code.blank?

      badge_class = case status_code
      when 200..299
        "badge-success"
      when 300..399
        "badge-info"
      when 400..499
        "badge-warning"
      when 500..599
        "badge-danger"
      else
        "badge-secondary"
      end

      content_tag(:span, status_code, class: "badge #{badge_class}")
    end

    def format_duration(duration_ms)
      return "" if duration_ms.blank?

      if duration_ms < 1000
        "#{duration_ms.round(1)}ms"
      else
        "#{(duration_ms / 1000.0).round(2)}s"
      end
    end

    def truncate_message(message, length: 200)
      return "" if message.blank?

      truncate(message, length: length, separator: " ")
    end

    def highlight_search_term(text, query)
      return text if query.blank? || text.blank?

      highlight(text, query, highlighter: '<mark>\1</mark>')
    end

    def correlation_link(entry)
      links = []

      if entry.request_id.present?
        links << link_to("Request: #{entry.request_id[0..7]}",
                        request_timeline_path(entry.request_id),
                        class: "correlation-link")
      end

      if entry.job_id.present?
        links << link_to("Job: #{entry.job_id[0..7]}",
                        job_timeline_path(entry.job_id),
                        class: "correlation-link")
      end

      safe_join(links, " ")
    end
  end
end
