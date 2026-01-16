class GenerateLogsJob < ApplicationJob
  queue_as :default

  def perform(count: 50)
    # Generate logs using Rails logger
    # These flow through DirectLogger → RawEntry → Puma plugin → Entry
    Rails.logger.info "GenerateLogsJob: Starting to generate #{count} log entries"

    levels = %w[debug info warn error fatal]
    messages = [
      "Processing background task",
      "Database query completed",
      "API request successful",
      "Cache miss occurred",
      "Email sent to user",
      "File upload processed",
      "Background job executing",
      "Webhook received",
      "Data synchronization complete",
      "Report generated"
    ]

    count.times do |i|
      level = levels.sample
      message = messages.sample

      # Log using Rails logger (flows through DirectLogger)
      Rails.logger.send(level, "#{message} (##{i + 1})")

      # Sleep briefly to simulate work
      sleep 0.01 if i % 10 == 0
    end

    Rails.logger.info "GenerateLogsJob: Completed generating #{count} log entries"
  end
end
