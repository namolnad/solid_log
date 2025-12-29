require_relative "lib/solid_log/service/version"

Gem::Specification.new do |spec|
  spec.name        = "solid_log-service"
  spec.version     = SolidLog::Service::VERSION
  spec.authors     = ["Dan Loman"]
  spec.email       = ["daniel.h.loman@gmail.com"]
  spec.homepage    = "https://github.com/namolnad/solid_log"
  spec.summary     = "Standalone log ingestion and processing service for SolidLog"
  spec.description = "Provides HTTP API for log ingestion, background processing with built-in Scheduler, and query APIs. Can run as standalone service or integrate with existing Rails apps."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/namolnad/solid_log"
  spec.metadata["changelog_uri"] = "https://github.com/namolnad/solid_log/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,bin,config,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md", "config.ru"]
  end

  spec.bindir = "bin"
  spec.executables = ["solid_log_service"]

  spec.add_dependency "solid_log-core", "~> 0.1.0"
  spec.add_dependency "rails", ">= 8.0.2"
  spec.add_dependency "puma", "~> 6.0"

  # Development dependencies
  spec.add_development_dependency "sqlite3", ">= 2.1"
  spec.add_development_dependency "minitest", ">= 5.0"
  spec.add_development_dependency "combustion", "~> 1.4"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "debug"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "rubocop-rails-omakase"
  spec.add_development_dependency "rack-cors"
  spec.add_development_dependency "solid_cable"
end
