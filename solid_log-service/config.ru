# This file is used by Rack-based servers to start the application.
require 'rubygems'

# Only require bundler/setup if not using global gems (development/test)
# In production Docker, gems are installed globally and SKIP_BUNDLER is set
require 'bundler/setup' unless ENV['SKIP_BUNDLER'] == 'true'

require 'active_support'
require 'active_support/core_ext'
require 'active_record'
require 'action_cable'

# Set up ActiveRecord database connection
url = ENV["SOLIDLOG_DATABASE_URL"] || ENV["DATABASE_URL"]
adapter = ENV["SOLIDLOG_DB_ADAPTER"] || ENV["DB_ADAPTER"] || "sqlite3"
pool = ENV.fetch("RAILS_MAX_THREADS", 5).to_i

db_config = if url&.include?("://")
  { url: url, pool: pool }
else
  { adapter: adapter, database: url || "storage/production_log.sqlite3", pool: pool }
end

ActiveRecord::Base.establish_connection(db_config)

# Load solid_log gems
require 'solid_log/core'
require_relative 'lib/solid_log/service'

# Configure ActionCable for live-tailing
cable_config_path = File.join(__dir__, 'config', 'cable.yml')
if File.exist?(cable_config_path)
  require 'yaml'
  env = ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'production'
  cable_config = YAML.load_file(cable_config_path)[env]
  ActionCable.server.config.cable = cable_config if cable_config
end
ActionCable.server.config.logger = SolidLog::Service.logger

# Load configuration file if it exists
config_file = File.join(__dir__, 'config', 'solid_log_service.rb')
require config_file if File.exist?(config_file)

# Start job processor
SolidLog::Service.start!

# Shutdown hook
at_exit { SolidLog::Service.stop! }

# Run Rack app
run SolidLog::Service::RackApp.new
