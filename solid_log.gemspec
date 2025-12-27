require_relative "lib/solid_log/version"

Gem::Specification.new do |spec|
  spec.name        = "solid_log"
  spec.version     = SolidLog::VERSION
  spec.authors     = [ "Dan Loman" ]
  spec.email       = [ "daniel.h.loman@gmail.com" ]
  spec.homepage    = "https://github.com/namolnad/solid_log"
  spec.summary     = "Self-hosted log management for Rails applications"
  spec.description = "SolidLog is a Rails-native log ingestion and viewing service that eliminates the need for paid log viewers. Supports SQLite, PostgreSQL, and MySQL with database-native full-text search and a Mission Control-style UI."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/namolnad/solid_log"
  spec.metadata["changelog_uri"] = "https://github.com/namolnad/solid_log/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md", "app/assets/**/*"]
  end

  spec.add_dependency "rails", ">= 8.0.2"
  spec.add_dependency "sqlite3", ">= 2.1"
  spec.add_dependency "bcrypt", "~> 3.1"
  spec.add_dependency "propshaft", ">= 1.0"
  spec.add_dependency "importmap-rails"
  spec.add_dependency "turbo-rails"
  spec.add_dependency "stimulus-rails"
end
