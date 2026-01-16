# SolidLog configuration for test app

SolidLog.configure do |config|
  # Use separate database for SolidLog (can also use main DB)
  config.database_url = ENV['SOLIDLOG_DATABASE_URL'] || "sqlite3:#{Rails.root}/../../db/solid_log_test.sqlite3"

  # Enable inline parsing
  config.inline_parsing_enabled = true

  # Fast polling for testing (5 seconds)
  config.parse_interval = 5

  # Smaller batches for testing
  config.parser_batch_size = 100

  # Retention
  config.retention_days = 7
  config.error_retention_days = 30
end
