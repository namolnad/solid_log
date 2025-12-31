require_relative "lib/solid_log/ui/version"

Gem::Specification.new do |spec|
  spec.name        = "solid_log-ui"
  spec.version     = SolidLog::UI::VERSION
  spec.authors     = ["Dan Loman"]
  spec.email       = ["daniel.h.loman@gmail.com"]
  spec.homepage    = "https://github.com/namolnad/solid_log"
  spec.summary     = "Web UI for viewing SolidLog entries"
  spec.description = "Mission Control-style web interface for SolidLog. Supports direct database access or HTTP API mode. Mount in your Rails app for log viewing."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/namolnad/solid_log"
  spec.metadata["changelog_uri"] = "https://github.com/namolnad/solid_log/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "solid_log-core", "~> 0.1.0"
  spec.add_dependency "rails", ">= 8.0.2"
  spec.add_dependency "importmap-rails"
  spec.add_dependency "turbo-rails"
  spec.add_dependency "stimulus-rails"

  # Development dependencies
  spec.add_development_dependency "sqlite3", ">= 2.1"
  spec.add_development_dependency "minitest", "~> 6.0"
  spec.add_development_dependency "combustion", "~> 1.3"
  spec.add_development_dependency "rails-controller-testing"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "debug"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "rubocop-rails-omakase"
end
