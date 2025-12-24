module SolidLog
  class CorrelationService
    def self.timeline_for_request(request_id)
      return [] if request_id.blank?

      entries = Entry.by_request_id(request_id).recent

      group_timeline_entries(entries)
    end

    def self.timeline_for_job(job_id)
      return [] if job_id.blank?

      entries = Entry.by_job_id(job_id).recent

      group_timeline_entries(entries)
    end

    private

    def self.group_timeline_entries(entries)
      # Group by controller/action or message pattern
      grouped = entries.group_by do |entry|
        if entry.controller.present?
          "#{entry.controller}##{entry.action}"
        else
          # Group similar messages
          entry.message&.first(50) || "unknown"
        end
      end

      # Convert to timeline format
      grouped.map do |key, group_entries|
        {
          label: key,
          entries: group_entries,
          start_time: group_entries.last.created_at,
          end_time: group_entries.first.created_at,
          duration: calculate_duration(group_entries),
          entry_count: group_entries.size
        }
      end.sort_by { |g| g[:start_time] }
    end

    def self.calculate_duration(entries)
      return 0 if entries.size < 2

      start_time = entries.last.created_at
      end_time = entries.first.created_at

      ((end_time - start_time) * 1000).round(2) # milliseconds
    end
  end
end
