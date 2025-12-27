module SolidLog
  module ApplicationCable
    class Connection < ActionCable::Connection::Base
      # No authentication needed for log streaming
      # In production, you might want to add token-based auth
    end
  end
end
