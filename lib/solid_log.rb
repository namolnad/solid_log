require_relative "solid_log/version"
require_relative "solid_log/configuration"
require_relative "solid_log/engine"
require_relative "solid_log/parser"
require_relative "solid_log/adapters/base_adapter"
require_relative "solid_log/adapters/sqlite_adapter"
require_relative "solid_log/adapters/postgresql_adapter"
require_relative "solid_log/adapters/mysql_adapter"
require_relative "solid_log/adapters/adapter_factory"

# Optional: LogSubscriber for Rails integration (loaded on-demand)
# require_relative "solid_log/log_subscriber"

if defined?(Rails::Generators)
  require "generators/solid_log/install/install_generator"
end

module SolidLog
  class << self
    attr_accessor :database
    attr_writer :configuration
  end

  self.database = :log

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield(configuration)
  end

  def self.reset_configuration!
    @configuration = Configuration.new
  end

  def self.without_logging
    Thread.current[:solid_log_silenced] = true
    ActiveRecord::Base.logger.silence do
      yield
    end
  ensure
    Thread.current[:solid_log_silenced] = nil
  end

  def self.adapter
    Adapters::AdapterFactory.adapter
  end
end
