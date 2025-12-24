module SolidLog
  module EntriesHelper
    # Entry-specific helpers (not shared across other controllers)

    def truncate_message(message, length: 200)
      return "" if message.blank?

      truncate(message, length: length, separator: " ")
    end

    def pretty_json(json_string)
      return "" if json_string.blank?

      hash = JSON.parse(json_string)
      JSON.pretty_generate(hash)
    rescue JSON::ParserError
      json_string
    end
  end
end
