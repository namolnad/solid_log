module SolidLog
  class LogStreamChannel < ApplicationCable::Channel
    def subscribed
      # For now, stream all logs to all subscribers
      # TODO: Implement filter-based streaming in the future
      stream_from "solid_log_stream_all"
    end

    def unsubscribed
      # Cleanup when channel is unsubscribed
      stop_all_streams
    end
  end
end
