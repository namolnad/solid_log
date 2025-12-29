require_relative "lib/solid_log/core/version"

Gem::Specification.new do |spec|
  spec.name        = "solid_log-core"
  spec.version     = SolidLog::Core::VERSION
  spec.authors     = [ "Dan Loman" ]
  spec.email       = [ "daniel.h.loman@gmail.com" ]
  spec.homepage    = "https://github.com/namolnad/solid_log"
  spec.summary     = "Core models and database adapters for SolidLog"
  spec.description = "Provides shared models, database adapters, parser, and HTTP client for SolidLog service and UI gems. Supports SQLite, PostgreSQL, and MySQL."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/namolnad/solid_log"
  spec.metadata["changelog_uri"] = "https://github.com/namolnad/solid_log/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  # Rails components (not full Rails framework)
  spec.add_dependency "activerecord", ">= 8.0.2"
  spec.add_dependency "activesupport", ">= 8.0.2"
  spec.add_dependency "activejob", ">= 8.0.2"

  # Database adapters are optional - install only what you need
  # spec.add_dependency "sqlite3", ">= 2.1"   # For SQLite
  # spec.add_dependency "pg", ">= 1.1"        # For PostgreSQL
  # spec.add_dependency "mysql2", ">= 0.5"    # For MySQL

  # Development dependencies
  spec.add_development_dependency "sqlite3", ">= 2.1"
  spec.add_development_dependency "minitest", ">= 5.0"
  spec.add_development_dependency "concurrent-ruby", ">= 1.0"
  spec.add_development_dependency "rack", ">= 3.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "debug"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "rubocop-rails-omakase"
end
