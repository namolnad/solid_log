class GenerateLogsJob < ApplicationJob
  queue_as :default

  def perform(count: 50)
    Rails.logger.info "GenerateLogsJob: Starting to generate #{count} log entries"

    token = SolidLog::Token.first_or_create!(
      name: "Background Job Token",
      token_hash: SolidLog::Token.send(:hash_token, "job_token_#{SecureRandom.hex(8)}")
    )

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

      # Log using Rails logger
      Rails.logger.send(level, "#{message} (##{i + 1})")

      # Also create raw entry
      SolidLog::RawEntry.create!(
        token: token,
        payload: {
          timestamp: Time.current.iso8601,
          level: level,
          message: "#{message} (##{i + 1})",
          app: "test_app",
          env: Rails.env,
          job_id: job_id,
          job_class: self.class.name,
          iteration: i + 1,
          extra_data: {
            queue_name: queue_name,
            priority: priority,
            executions: executions
          }
        }.to_json,
        received_at: Time.current
      )

      # Sleep briefly to simulate work
      sleep 0.01 if i % 10 == 0
    end

    Rails.logger.info "GenerateLogsJob: Completed generating #{count} log entries"
  end
end
