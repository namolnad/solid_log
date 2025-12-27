module SolidLog
  class LiveTailBroadcaster
    # Broadcast new entries to live tail subscribers
    # Called after entries are inserted by the parser
    def self.broadcast_entries(entry_ids)
      return unless SolidLog.configuration.live_tail_mode == :websocket
      return unless defined?(ActionCable)
      return if entry_ids.empty?

      entries = Entry.where(id: entry_ids).order(:id)

      entries.each do |entry|
        # Render the entry HTML
        html = ApplicationController.render(
          partial: "solid_log/streams/log_row",
          locals: { entry: entry, query: nil }
        )

        # Broadcast to all connected clients
        # In the future, we could filter by user filters
        ActionCable.server.broadcast(
          "solid_log_stream_all",
          { html: html, entry_id: entry.id }
        )
      end
    end
  end
end
