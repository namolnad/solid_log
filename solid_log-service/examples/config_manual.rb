# Example: SolidLog Service with Manual Job Scheduling (Cron)
# Place this in: config/solid_log_service.rb
#
# Use this when you want full control over job scheduling via cron or systemd timers

SolidLog::Service.configure do |config|
  # Database connection
  config.database_url = ENV['DATABASE_URL'] || 'sqlite3:///app/storage/production_log.sqlite'

  # Job processing mode
  config.job_mode = :manual  # No automatic job scheduling

  # Retention policies (used when jobs run)
  config.retention_days = 30
  config.error_retention_days = 90

  # Other settings...
  config.max_batch_size = 1000
  config.facet_cache_ttl = 5.minutes
  config.auto_promote_fields = false
end

# Then set up cron jobs:
#
# Edit crontab: crontab -e
#
# Parse logs every 10 seconds (use systemd timer for sub-minute intervals)
# */1 * * * * cd /app && bundle exec rails solid_log:parse_logs
#
# Cache cleanup every hour
# 0 * * * * cd /app && bundle exec rails solid_log:cache_cleanup
#
# Retention cleanup daily at 2 AM
# 0 2 * * * cd /app && bundle exec rails solid_log:retention[30]
#
# Field analysis daily at 3 AM
# 0 3 * * * cd /app && bundle exec rails solid_log:field_analysis

# Or use systemd timers for sub-minute intervals:
#
# /etc/systemd/system/solidlog-parser.service:
# [Unit]
# Description=SolidLog Parser
#
# [Service]
# Type=oneshot
# WorkingDirectory=/app
# ExecStart=/usr/bin/bundle exec rails solid_log:parse_logs
# User=deploy
#
# /etc/systemd/system/solidlog-parser.timer:
# [Unit]
# Description=SolidLog Parser Timer
#
# [Timer]
# OnBootSec=10s
# OnUnitActiveSec=10s
#
# [Install]
# WantedBy=timers.target
#
# Enable: systemctl enable --now solidlog-parser.timer
