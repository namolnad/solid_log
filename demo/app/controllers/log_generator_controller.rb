class LogGeneratorController < ApplicationController
  def index
    # Show log generation UI
  end

  def generate
    # Generate a standalone log entry with a message via Rails.logger
    # We use a Thread so it's not captured by lograge as part of the HTTP request
    level = params[:level] || "info"
    message = params[:message] || "Test log entry at #{Time.current}"

    # Log in a separate thread so lograge doesn't capture it as HTTP request data
    # Rails.logger is configured to use DirectLogger, so this will flow to SolidLog
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        # Log through Rails.logger with just a plain string message
        # DirectLogger will wrap it with timestamp and structure it
        case level
        when "debug"
          Rails.logger.debug(message)
        when "info"
          Rails.logger.info(message)
        when "warn"
          Rails.logger.warn(message)
        when "error"
          Rails.logger.error(message)
        when "fatal"
          Rails.logger.fatal(message)
        else
          Rails.logger.info(message)
        end
      end
    end

    redirect_to root_path, notice: "Generated #{level} log: #{message}"
  end

  def generate_batch
    # Generate batch of logs via Rails.logger in a background thread
    # This keeps them separate from the HTTP request log
    count = (params[:count] || 10).to_i
    count = [count, 1000].min # Max 1000 at a time

    # Generate in background to avoid blocking the request
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        levels = %w[debug info warn error fatal]
        messages = [
          "Processing user request",
          "Database query completed successfully",
          "Cache hit for key: users/active",
          "API response received in 45ms",
          "Email sent to user@example.com",
          "File uploaded: document.pdf",
          "Background job completed",
          "Webhook received from payment provider",
          "Data synchronization finished",
          "Report generated: monthly_summary.xlsx",
          "Session expired for user",
          "Invalid authentication token",
          "Rate limit exceeded",
          "Database connection pool exhausted",
          "External API timeout"
        ]

        batch_id = SecureRandom.uuid
        count.times do |i|
          level = levels.sample
          message = "#{messages.sample} (##{i + 1})"

          # Log through Rails.logger (configured to use DirectLogger)
          Rails.logger.send(level, message)
        end
      end
    end

    redirect_to root_path, notice: "Generating #{count} log entries in background..."
  end

  def trigger_job
    # Enqueue background job that generates logs
    GenerateLogsJob.perform_later(count: params[:count].to_i || 50)
    redirect_to root_path, notice: "Enqueued background job to generate logs"
  end

  def clear_logs
    # Clear all logs from both raw_entries and entries tables
    # Wrap in without_logging to prevent logging the deletion
    SolidLog.without_logging do
      raw_count = SolidLog::RawEntry.count
      entry_count = SolidLog::Entry.count

      SolidLog::Entry.delete_all
      SolidLog::RawEntry.delete_all

      # Also clear facet cache and tokens if needed
      SolidLog::FacetCache.delete_all if defined?(SolidLog::FacetCache)

      Rails.logger.info "Cleared #{raw_count} raw entries and #{entry_count} parsed entries"
    end

    redirect_to root_path, notice: "All logs cleared successfully"
  end

  def run_retention
    # Run retention job manually
    SolidLog.without_logging do
      stats = SolidLog::Core::Jobs::RetentionJob.perform_now

      message = "Retention complete: deleted #{stats[:entries_deleted]} entries, #{stats[:raw_deleted]} raw entries"
      redirect_to root_path, notice: message
    end
  end
end
