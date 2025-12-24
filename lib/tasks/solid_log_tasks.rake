namespace :solid_log do
  namespace :install do
    desc "Copy migrations from solid_log to application"
    task :migrations do
      ENV["FROM"] = "solid_log"
      Rake::Task["railties:install:migrations"].invoke
    end
  end

  desc "Parse unparsed log entries from raw table to entries table"
  task parse_logs: :environment do
    SolidLog::ParserJob.perform_now
  end

  desc "Parse logs with specified batch size"
  task :parse_logs_batch, [ :batch_size ] => :environment do |t, args|
    batch_size = (args[:batch_size] || 100).to_i
    SolidLog::ParserJob.perform_now(batch_size: batch_size)
  end

  desc "Setup periodic log processing (add to crontab or scheduler)"
  task :schedule_info do
    puts "Add this to your crontab or scheduler to parse logs every 5 minutes:"
    puts "*/5 * * * * cd #{Rails.root} && bundle exec rake solid_log:parse_logs"
    puts ""
    puts "Or use whenever gem in schedule.rb:"
    puts "every 5.minutes do"
    puts "  rake 'solid_log:parse_logs'"
    puts "end"
    puts ""
    puts "Or use Solid Queue recurring task:"
    puts "SolidLog::ParserJob.set(wait: 5.minutes).perform_later"
  end

  desc "Clean up old log entries (older than 30 days by default)"
  task :cleanup, [ :days ] => :environment do |t, args|
    days = (args[:days] || 30).to_i
    threshold = days.days.ago

    entry_count = nil
    raw_count = nil

    SolidLog.without_logging do
      # Delete old entries
      entry_count = SolidLog::Entry.where("created_at < ?", threshold).delete_all

      # Delete old parsed raw entries (keep recent for audit trail)
      raw_count = SolidLog::RawEntry.parsed.where("parsed_at < ?", threshold).delete_all
    end

    puts "Deleted #{entry_count} old entries"
    puts "Deleted #{raw_count} old parsed raw entries"
  end

  desc "Analyze field usage and recommend promotions"
  task analyze_fields: :environment do
    SolidLog.without_logging do
      puts "Field Usage Analysis"
      puts "=" * 80

      hot_fields = SolidLog::Field.hot_fields(1000).limit(20)

      if hot_fields.empty?
        puts "No high-usage fields found yet."
        puts "Fields with usage count >= 1000 will appear here."
      else
        puts sprintf("%-30s %10s %10s %s", "Field Name", "Usage", "Type", "Promoted?")
        puts "-" * 80

        hot_fields.each do |field|
          promoted = field.promoted? ? "Yes" : "No"
          puts sprintf("%-30s %10d %10s %s", field.name, field.usage_count, field.type, promoted)
        end

        puts ""
        puts "Consider promoting high-usage fields to dedicated columns for better query performance."
        puts "Use: rails g solid_log:promote_field <field_name>"
      end
    end
  end

  desc "Show stats about log storage"
  task stats: :environment do
    SolidLog.without_logging do
      raw_total = SolidLog::RawEntry.count
      raw_unparsed = SolidLog::RawEntry.unparsed.count
      entries_total = SolidLog::Entry.count
      fields_total = SolidLog::Field.count

      puts "SolidLog Statistics"
      puts "=" * 80
      puts sprintf("%-30s %d", "Raw entries (total):", raw_total)
      puts sprintf("%-30s %d", "Raw entries (unparsed):", raw_unparsed)
      puts sprintf("%-30s %d", "Parsed entries:", entries_total)
      puts sprintf("%-30s %d", "Tracked fields:", fields_total)
      puts ""

      if entries_total > 0
        oldest = SolidLog::Entry.order(:created_at).first
        newest = SolidLog::Entry.order(created_at: :desc).first
        puts sprintf("%-30s %s", "Oldest entry:", oldest.created_at.to_s)
        puts sprintf("%-30s %s", "Newest entry:", newest.created_at.to_s)
        puts ""
      end

      # Log level distribution
      levels = SolidLog::Entry.group(:level).count.sort_by { |k, v| -v }
      if levels.any?
        puts "Log Level Distribution:"
        puts "-" * 80
        levels.each do |level, count|
          percentage = (count.to_f / entries_total * 100).round(1)
          puts sprintf("  %-10s %10d (%5.1f%%)", level, count, percentage)
        end
      end
    end
  end

  desc "Create an API token for log ingestion"
  task :create_token, [ :name ] => :environment do |t, args|
    name = args[:name] || "API Token #{Time.current.to_i}"

    SolidLog.without_logging do
      token = SolidLog::Token.generate!(name)

      puts "Token created successfully!"
      puts "=" * 80
      puts "Name:  #{token.name}"
      puts "Token: #{token.plaintext_token}"
      puts "=" * 80
      puts ""
      puts "IMPORTANT: Save this token now. It cannot be retrieved later."
      puts ""
      puts "Use in Authorization header:"
      puts "Authorization: Bearer #{token.plaintext_token}"
    end
  end

  desc "List all API tokens"
  task list_tokens: :environment do
    SolidLog.without_logging do
      tokens = SolidLog::Token.order(created_at: :desc)

      if tokens.empty?
        puts "No tokens found. Create one with: rake solid_log:create_token"
      else
        puts "API Tokens"
        puts "=" * 80
        puts sprintf("%-5s %-30s %-20s %-20s", "ID", "Name", "Created", "Last Used")
        puts "-" * 80

        tokens.each do |token|
          last_used = token.last_used_at ? token.last_used_at.to_s : "Never"
          puts sprintf("%-5d %-30s %-20s %-20s",
                      token.id,
                      token.name,
                      token.created_at.to_s(:short),
                      last_used)
        end
      end
    end
  end

  desc "Run retention cleanup (delete old entries)"
  task :retention, [ :days ] => :environment do |t, args|
    days = (args[:days] || 30).to_i
    SolidLog::RetentionJob.perform_now(retention_days: days)
  end

  desc "Run retention cleanup with VACUUM"
  task :retention_vacuum, [ :days ] => :environment do |t, args|
    days = (args[:days] || 30).to_i
    SolidLog::RetentionJob.perform_now(retention_days: days, vacuum: true)
  end

  desc "Clear expired cache entries"
  task cache_cleanup: :environment do
    SolidLog::CacheCleanupJob.perform_now
  end

  desc "Analyze fields and recommend promotions"
  task field_analysis: :environment do
    SolidLog::FieldAnalysisJob.perform_now(auto_promote: false)
  end

  desc "Auto-promote high-usage fields"
  task field_auto_promote: :environment do
    SolidLog::FieldAnalysisJob.perform_now(auto_promote: true)
  end

  desc "Show health metrics"
  task health: :environment do
    SolidLog.without_logging do
      metrics = SolidLog::HealthService.metrics

      puts "SolidLog Health Metrics"
      puts "=" * 80
      puts ""

      puts "INGESTION"
      puts "-" * 80
      puts sprintf("  %-30s %s", "Total raw entries:", metrics[:ingestion][:total_raw])
      puts sprintf("  %-30s %s", "Ingested today:", metrics[:ingestion][:today_raw])
      puts sprintf("  %-30s %s", "Ingested last hour:", metrics[:ingestion][:last_hour_raw])
      puts sprintf("  %-30s %s", "Last ingestion:", metrics[:ingestion][:last_ingestion] || "N/A")
      puts ""

      puts "PARSING"
      puts "-" * 80
      puts sprintf("  %-30s %s", "Unparsed entries:", metrics[:parsing][:unparsed_count])
      puts sprintf("  %-30s %s%%", "Backlog percentage:", metrics[:parsing][:parse_backlog_percentage])
      puts sprintf("  %-30s %s", "Stale unparsed (>1h):", metrics[:parsing][:stale_unparsed])
      puts sprintf("  %-30s %s", "Health status:", metrics[:parsing][:health_status])
      puts ""

      puts "STORAGE"
      puts "-" * 80
      puts sprintf("  %-30s %s", "Total entries:", metrics[:storage][:total_entries])
      puts sprintf("  %-30s %s", "Total fields:", metrics[:storage][:total_fields])
      puts sprintf("  %-30s %s", "Promoted fields:", metrics[:storage][:promoted_fields])
      puts sprintf("  %-30s %s", "Hot fields:", metrics[:storage][:hot_fields_count])
      puts sprintf("  %-30s %s", "Database size:", metrics[:storage][:database_size])
      puts ""

      puts "PERFORMANCE"
      puts "-" * 80
      puts sprintf("  %-30s %s", "Cache entries:", metrics[:performance][:cache_entries])
      puts sprintf("  %-30s %s", "Expired cache:", metrics[:performance][:expired_cache])
      puts sprintf("  %-30s %s%%", "Error rate (1h):", metrics[:performance][:error_rate])
      puts sprintf("  %-30s %sms", "Avg duration (1h):", metrics[:performance][:avg_duration])
    end
  end

  desc "Optimize database (PRAGMA optimize)"
  task optimize: :environment do
    SolidLog.without_logging do
      puts "Running PRAGMA optimize..."
      if SolidLog::RetentionService.optimize_database
        puts "Database optimized successfully"
      else
        puts "Failed to optimize database (check logs)"
      end
    end
  end
end
