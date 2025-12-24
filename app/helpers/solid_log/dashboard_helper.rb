module SolidLog
  module DashboardHelper
    def format_count(count)
      number_with_delimiter(count || 0)
    end

    def format_percentage(numerator, denominator)
      return "0%" if denominator.nil? || denominator.zero?

      percentage = (numerator.to_f / denominator * 100).round(1)
      "#{percentage}%"
    end

    def trend_indicator(current, previous)
      return "" if previous.nil? || previous.zero?

      change = ((current - previous).to_f / previous * 100).round(1)

      if change > 0
        content_tag(:span, "+#{change}%", class: "trend-up")
      elsif change < 0
        content_tag(:span, "#{change}%", class: "trend-down")
      else
        content_tag(:span, "0%", class: "trend-neutral")
      end
    end

    def time_ago_or_never(time)
      time ? time_ago_in_words(time) + " ago" : "Never"
    end

    def health_status_badge(unparsed_count)
      if unparsed_count == 0
        content_tag(:span, "Healthy", class: "badge badge-success")
      elsif unparsed_count < 100
        content_tag(:span, "OK", class: "badge badge-info")
      elsif unparsed_count < 1000
        content_tag(:span, "Warning", class: "badge badge-warning")
      else
        content_tag(:span, "Backlog", class: "badge badge-danger")
      end
    end
  end
end
