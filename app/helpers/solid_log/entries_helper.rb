module SolidLog
  module EntriesHelper
    # Entry-specific helpers (not shared across other controllers)

    def pretty_json(json_string)
      return "" if json_string.blank?

      hash = JSON.parse(json_string)
      JSON.pretty_generate(hash)
    rescue JSON::ParserError
      json_string
    end
  end
end
