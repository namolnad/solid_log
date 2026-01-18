module SolidLog
  module UI
    class LiveTailBroadcaster
      # Broadcast new entries to live tail subscribers
      # Called after entries are inserted by the parser
      def self.broadcast_entries(entry_ids)
        return unless SolidLog::UI.configuration.websocket_enabled
        return unless defined?(ActionCable)
        return if entry_ids.empty?

        entries = SolidLog::Entry.where(id: entry_ids).order(:id)

        # Get all unique filter combinations currently subscribed
        # We'll broadcast each entry to all matching filter streams
        active_filters = get_active_filter_streams

        entries.each do |entry|
          # Render the entry HTML once
          html = ApplicationController.render(
            partial: "solid_log/ui/streams/log_row",
            locals: { entry: entry, query: nil }
          )

          # Broadcast to each filter stream where this entry matches
          active_filters.each do |filter_key, filters|
            if entry_matches_filters?(entry, filters)
              stream_name = "solid_log_stream_#{filter_key}"
              ActionCable.server.broadcast(
                stream_name,
                {
                  html: html,
                  entry_id: entry.id
                }
              )
            end
          end
        end
      end

      private

      def self.get_active_filter_streams
        # Get all currently active filter combinations from Rails.cache
        # This works across all processes and survives restarts (within cache TTL)
        if defined?(SolidLog::UI::LogStreamChannel)
          SolidLog::UI::LogStreamChannel.active_filter_combinations
        else
          # Fallback: just check empty filters
          { generate_filter_key({}) => {} }
        end
      end

      def self.entry_matches_filters?(entry, filters)
        return true if filters.empty?

        # Check each filter
        filters.each do |key, values|
          values = Array(values).reject(&:blank?)
          next if values.empty?

          entry_value = entry.public_send(key) rescue nil

          # If entry doesn't have this field and filter requires it, no match
          return false if entry_value.nil?

          # Check if entry value matches any of the filter values
          unless values.map(&:to_s).include?(entry_value.to_s)
            return false
          end
        end

        true
      end

      def self.generate_filter_key(filters)
        normalized = filters.sort.to_h
        Digest::MD5.hexdigest(normalized.to_json)
      end
    end
  end
end
