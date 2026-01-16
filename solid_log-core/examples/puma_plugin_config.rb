# Example: Using SolidLog with Puma Plugin
# Place this in: config/initializers/solid_log.rb
#
# This enables inline log parsing via a background thread in your Puma process.
# No separate service or worker process needed!

SolidLog.configure do |config|
  # Database connection (can be separate from main app DB)
  config.database_url = ENV['SOLIDLOG_DATABASE_URL'] || "sqlite3:#{Rails.root}/db/solid_log.sqlite3"

  # Enable inline parsing
  config.inline_parsing_enabled = true

  # Polling interval (how often to check for unparsed entries)
  config.parse_interval = 10  # seconds (default: 10)

  # Batch size (how many entries to process per cycle)
  config.parser_batch_size = 1000  # entries (default: 1000)

  # Retention policies
  config.retention_days = 30
  config.error_retention_days = 90

  # Optional: Custom broadcast callback for ActionCable
  # config.after_entries_inserted = ->(entry_ids) do
  #   # Your custom logic here
  #   # Example: Broadcast to custom channel, send webhook, etc.
  # end
end

# Then in config/puma.rb, add:
#   plugin :solid_log if ENV["SOLIDLOG_PUMA_PLUGIN_ENABLED"]
#
# And in .env:
#   SOLIDLOG_PUMA_PLUGIN_ENABLED=true
#
# That's it! Puma will automatically parse logs in the background.

# Performance characteristics:
# - Throughput: ~6,000 entries/minute (1000 batch × 6 cycles/min)
# - Memory: +5-10MB
# - CPU: ~1-5% during parsing, idle otherwise

# When to use:
# - Small to medium Rails apps
# - Low to medium log volume (<10K entries/min)
# - Simple deployments (single dyno/container)
# - Teams wanting zero-config solution

# When NOT to use:
# - High log volume (>10K entries/min) → use Solid Queue job
# - Very high volume (>50K entries/min) → use solid_log-service
# - Multiple apps → use solid_log-service for centralized logging
