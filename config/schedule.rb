# Example schedule.rb for whenever gem
# Add this to your application's config/schedule.rb if using whenever

every 5.minutes do
  rake "solid_log:process_logs"
end

# Optional: Clean up old logs daily
every 1.day, at: '2:00 am' do
  rake "solid_log:cleanup"
end