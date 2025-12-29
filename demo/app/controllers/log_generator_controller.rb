class LogGeneratorController < ApplicationController
  def index
    # Show log generation UI
  end

  def generate
    # Generate a single log entry
    level = params[:level] || "info"
    message = params[:message] || "Test log entry at #{Time.current}"

    # Log using Rails logger (will be captured by SolidLog if configured)
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

    # Also create a raw entry directly for testing
    token = SolidLog::Token.first_or_create!(
      name: "Test Token",
      token_hash: SolidLog::Token.send(:hash_token, "test_token_#{SecureRandom.hex(8)}")
    )

    SolidLog::RawEntry.create!(
      token: token,
      payload: {
        timestamp: Time.current.iso8601,
        level: level,
        message: message,
        app: "test_app",
        env: Rails.env,
        request_id: request.request_id,
        extra_data: {
          controller: controller_name,
          action: action_name,
          ip: request.remote_ip
        }
      }.to_json,
      received_at: Time.current
    )

    redirect_to root_path, notice: "Generated #{level} log: #{message}"
  end

  def generate_batch
    count = (params[:count] || 10).to_i
    count = [count, 1000].min # Max 1000 at a time

    token = SolidLog::Token.first_or_create!(
      name: "Batch Token",
      token_hash: SolidLog::Token.send(:hash_token, "batch_token_#{SecureRandom.hex(8)}")
    )

    levels = %w[debug info warn error fatal]
    base_time = Time.current

    count.times do |i|
      level = levels.sample
      # Spread timestamps over the last 10 minutes (600 seconds / count)
      # This makes batch logs appear more realistic with varied timestamps
      timestamp = base_time - (count - i) * (600.0 / count)

      SolidLog::RawEntry.create!(
        token: token,
        payload: {
          timestamp: timestamp.iso8601,
          level: level,
          message: "Batch log entry ##{i + 1}",
          app: "test_app",
          env: Rails.env,
          batch_number: i + 1
        }.to_json,
        received_at: Time.current
      )
    end

    redirect_to root_path, notice: "Generated #{count} log entries"
  end

  def trigger_job
    # Enqueue background job that generates logs
    GenerateLogsJob.perform_later(count: params[:count].to_i || 50)
    redirect_to root_path, notice: "Enqueued background job to generate logs"
  end
end
