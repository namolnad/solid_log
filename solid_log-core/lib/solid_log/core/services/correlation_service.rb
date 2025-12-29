module SolidLog
  module Core
    class CorrelationService
      # Get all entries for a specific request ID in timeline order
      def self.request_timeline(request_id)
        return Entry.none if request_id.blank?

        Entry.by_request_id(request_id).recent
      end

      # Get all entries for a specific job ID in timeline order
      def self.job_timeline(job_id)
        return Entry.none if job_id.blank?

        Entry.by_job_id(job_id).recent
      end

      # Get correlation stats for a request
      def self.request_stats(request_id)
        entries = request_timeline(request_id)

        {
          total_entries: entries.count,
          duration: calculate_duration(entries),
          levels: entries.group(:level).count,
          first_timestamp: entries.first&.timestamp,
          last_timestamp: entries.last&.timestamp
        }
      end

      # Get correlation stats for a job
      def self.job_stats(job_id)
        entries = job_timeline(job_id)

        {
          total_entries: entries.count,
          duration: calculate_duration(entries),
          levels: entries.group(:level).count,
          first_timestamp: entries.first&.timestamp,
          last_timestamp: entries.last&.timestamp
        }
      end

      # Find related entries (same request_id or job_id)
      def self.find_related(entry)
        related = []

        if entry.request_id.present?
          related += request_timeline(entry.request_id).where.not(id: entry.id).to_a
        end

        if entry.job_id.present?
          related += job_timeline(entry.job_id).where.not(id: entry.id).to_a
        end

        related.uniq.sort_by(&:timestamp)
      end

      private

      # Calculate total duration from first to last entry
      def self.calculate_duration(entries)
        return nil if entries.count < 2

        first = entries.first
        last = entries.last

        return nil unless first&.timestamp && last&.timestamp

        ((last.timestamp - first.timestamp) * 1000).round # milliseconds
      end
    end
  end
end
