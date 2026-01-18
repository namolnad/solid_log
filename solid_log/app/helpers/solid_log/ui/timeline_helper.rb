module SolidLog
  module UI
    module TimelineHelper
      def timeline_duration_bar(duration, max_duration)
        return "" if duration.nil? || max_duration.nil? || max_duration.zero?

        width_percentage = [(duration.to_f / max_duration * 100), 100].min
        content_tag(:div, "", class: "timeline-duration-bar", style: "width: #{format('%.1f', width_percentage)}%")
      end

      def format_timeline_duration(duration_ms)
        return "N/A" if duration_ms.nil?

        if duration_ms < 1
          "< 1ms"
        elsif duration_ms < 1000
          format("%.1fms", duration_ms)
        else
          format("%.1fs", duration_ms / 1000.0)
        end
      end

      def timeline_event_icon(entry)
        case entry.level
        when "error", "fatal"
          "⚠️"
        when "warn"
          "⚡"
        when "info"
          "ℹ️"
        when "debug"
          "🔍"
        else
          "•"
        end
      end
    end
  end
end
