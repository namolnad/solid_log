module SolidLogTestHelpers
  # Create a test token
  def create_test_token(name: "Test Token")
    SolidLog::Token.generate!(name)
  end

  # Create a raw entry
  def create_raw_entry(token: nil, payload: nil)
    token ||= create_test_token
    payload ||= { message: "Test log entry", level: "info", timestamp: Time.current.iso8601 }

    SolidLog::RawEntry.create!(
      token_id: token.id,
      payload: payload.to_json
    )
  end

  # Create a parsed entry
  def create_entry(attributes = {})
    defaults = {
      level: "info",
      created_at: Time.current,
      message: "Test log message"
    }

    SolidLog::Entry.create!(defaults.merge(attributes))
  end

  # Parse JSON response body
  def json_response
    JSON.parse(response.body)
  end

  # Create auth header for API requests
  def auth_header(token)
    { "Authorization" => "Bearer #{token.plaintext_token}" }
  end
end
