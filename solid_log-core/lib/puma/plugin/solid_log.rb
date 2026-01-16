# frozen_string_literal: true

require "puma/plugin"

# Puma plugin for inline SolidLog parsing
#
# This plugin spawns a background thread that continuously polls for unparsed
# raw log entries and processes them using BatchParsingService.
#
# Usage in config/puma.rb:
#   plugin :solid_log if ENV["SOLIDLOG_PUMA_PLUGIN_ENABLED"]
#
# Configuration:
#   SOLIDLOG_PUMA_PLUGIN_ENABLED=true
#   SOLIDLOG_INLINE_PARSING_ENABLED=true
#   SOLIDLOG_PARSE_INTERVAL=10
#   SOLIDLOG_PARSER_BATCH_SIZE=200
Puma::Plugin.create do
  def start(launcher)
    @launcher = launcher

    # Only start if we're actually in Puma server mode
    # Don't start in console, rails runner, rake tasks, etc.
    return unless puma_server_mode?

    # Only start if explicitly enabled
    return unless enabled?

    # Startup logs to STDERR to avoid recursion
    $stderr.puts "[SolidLog Puma Plugin] Starting inline parsing"
    $stderr.puts "[SolidLog Puma Plugin]   Parse interval: #{config.parse_interval}s"
    $stderr.puts "[SolidLog Puma Plugin]   Batch size: #{config.parser_batch_size}"

    # Start background thread using Puma's in_background helper
    in_background do
      parser_loop
    end
  end

  private

  # Check if we're actually running as a Puma server
  # Returns false for console, rails runner, rake tasks, etc.
  def puma_server_mode?
    # Check if launcher is present and valid
    return false unless @launcher
    return false unless @launcher.respond_to?(:binder)

    # Check if we're not in a Rails console or runner
    # Console and runner set DISABLE_SPRING or have IRB/Runner in ARGV
    return false if defined?(Rails::Console)
    return false if $PROGRAM_NAME.include?("rake")
    return false if $PROGRAM_NAME.include?("runner")
    return false if ARGV.include?("console")
    return false if ARGV.include?("runner")
    return false if ARGV.include?("c")

    # If we made it here, we're likely in server mode
    true
  end

  # Main parser loop that runs continuously until Puma shutdown
  def parser_loop
    loop do
      # Thread will be killed by Puma on shutdown, no need to check running state

      begin
        # Ensure database connection in this thread
        # Pattern from DirectLogger (lines 155-158)
        ActiveRecord::Base.connection_pool.with_connection do
          # Process batch using shared service
          stats = SolidLog::Core::Services::BatchParsingService.process_batch(
            batch_size: config.parser_batch_size,
            logger: logger,
            broadcast_callback: method(:broadcast_callback)
          )

          # Log stats if entries were processed (to STDERR to avoid recursion)
          log_stats(stats) if stats[:processed] > 0
        end

        # Normal sleep between cycles
        sleep config.parse_interval
      rescue => e
        # Log error to STDERR to avoid recursion
        $stderr.puts "[SolidLog Puma Plugin] ERROR: #{e.class} - #{e.message}"
        $stderr.puts e.backtrace.first(5).join("\n") if e.backtrace

        # Exponential backoff on error (max 60 seconds)
        # Prevents tight error loops
        backoff_time = [config.parse_interval * 2, 60].min
        $stderr.puts "[SolidLog Puma Plugin] Backing off for #{backoff_time}s" if ENV["SOLIDLOG_DEBUG"]
        sleep backoff_time
      end
    end

  rescue => e
    # Thread-level error - log to STDERR but don't crash Puma
    $stderr.puts "[SolidLog Puma Plugin] FATAL: #{e.class} - #{e.message}"
    $stderr.puts e.backtrace.join("\n") if e.backtrace
  ensure
    $stderr.puts "[SolidLog Puma Plugin] Parser loop exited"
  end

  # Check if plugin should be enabled
  def enabled?
    # Check ENV flag (explicit opt-in)
    return false if ENV["SOLIDLOG_PUMA_PLUGIN_ENABLED"] == "false"
    return false unless ENV["SOLIDLOG_PUMA_PLUGIN_ENABLED"]

    # Check configuration flag
    return false unless config.inline_parsing_enabled

    true
  rescue => e
    # If SolidLog isn't loaded yet, disable
    logger.error "SolidLog Puma Plugin: Configuration error: #{e.message}"
    false
  end

  # Get SolidLog configuration
  def config
    SolidLog.configuration
  end

  # Get logger instance
  def logger
    SolidLog.logger
  end

  # Broadcast callback for ActionCable
  def broadcast_callback(entry_ids)
    return if entry_ids.empty?

    if defined?(ActionCable) && ActionCable.server
      ActionCable.server.broadcast(
        "solid_log_new_entries",
        { entry_ids: entry_ids }
      )
      $stderr.puts "[SolidLog Puma Plugin] Broadcasted #{entry_ids.size} entries" if ENV["SOLIDLOG_DEBUG"]
    end
  rescue => e
    # Silent failure - broadcasting is optional
    $stderr.puts "[SolidLog Puma Plugin] Broadcast failed: #{e.message}" if ENV["SOLIDLOG_DEBUG"]
  end

  # Log processing stats (directly to STDERR to avoid recursion)
  def log_stats(stats)
    $stderr.puts "[SolidLog Puma Plugin] Processed #{stats[:processed]}, inserted #{stats[:inserted]}, errors #{stats[:errors]}" if ENV["SOLIDLOG_DEBUG"]
  end
end
