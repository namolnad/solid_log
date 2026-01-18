require "rake/testtask"

desc "Run tests for all gems"
task :test do
  puts "\n=== Running solid_log-core tests ==="
  system("cd solid_log-core && bundle exec rake test") || abort("Core tests failed")

  puts "\n=== Running solid_log-service tests ==="
  system("cd solid_log-service && bundle exec rake test") || abort("Service tests failed")

  puts "\n=== Running solid_log tests ==="
  system("cd solid_log && bundle exec rake test") || abort("UI tests failed")

  puts "\n=== All tests passed! ==="
end

namespace :test do
  desc "Run solid_log-core tests"
  task :core do
    system("cd solid_log-core && bundle exec rake test") || abort("Core tests failed")
  end

  desc "Run solid_log-service tests"
  task :service do
    system("cd solid_log-service && bundle exec rake test") || abort("Service tests failed")
  end

  desc "Run solid_log tests"
  task :ui do
    system("cd solid_log && bundle exec rake test") || abort("UI tests failed")
  end
end

namespace :release do
  desc "Bump version in all gems"
  task :bump, [:version] do |t, args|
    version = args[:version]
    abort("Usage: rake release:bump[X.Y.Z]") unless version && version.match?(/^\d+\.\d+\.\d+$/)

    puts "\n=== Bumping version to #{version} in all gems ==="

    version_files = [
      "solid_log-core/lib/solid_log/core/version.rb",
      "solid_log-service/lib/solid_log/service/version.rb",
      "solid_log/lib/solid_log/ui/version.rb"
    ]

    version_files.each do |file|
      content = File.read(file)
      updated = content.gsub(/VERSION = "[\d\.]+"/, "VERSION = \"#{version}\"")
      File.write(file, updated)
      puts "✓ Updated #{file}"
    end

    puts "\n=== Version bumped to #{version} ==="
    puts "\nNext steps:"
    puts "1. Review changes: git diff"
    puts "2. Run tests: rake test"
    puts "3. Commit: git commit -am 'Bump version to #{version}'"
    puts "4. Release: rake release:all"
  end

  desc "Build all gems"
  task :build do
    puts "\n=== Building all gems ==="

    # Build in order: core first, then service and ui
    puts "\nBuilding solid_log-core..."
    system("cd solid_log-core && bundle exec gem build solid_log-core.gemspec") || abort("Failed to build solid_log-core")

    puts "\nBuilding solid_log-service..."
    system("cd solid_log-service && bundle exec gem build solid_log-service.gemspec") || abort("Failed to build solid_log-service")

    puts "\nBuilding solid_log..."
    system("cd solid_log && bundle exec gem build solid_log.gemspec") || abort("Failed to build solid_log")

    puts "\n=== All gems built successfully! ==="
  end

  desc "Push all gems to RubyGems"
  task :push do
    require_relative "solid_log-core/lib/solid_log/core/version"
    version = SolidLog::Core::VERSION

    puts "\n=== Pushing all gems (version #{version}) to RubyGems ==="

    # Push in order: core first, then service and ui (since they depend on core)
    puts "\nPushing solid_log-core..."
    system("gem push solid_log-core/solid_log-core-#{version}.gem") || abort("Failed to push solid_log-core")

    puts "\nPushing solid_log-service..."
    system("gem push solid_log-service/solid_log-service-#{version}.gem") || abort("Failed to push solid_log-service")

    puts "\nPushing solid_log..."
    system("gem push solid_log/solid_log-#{version}.gem") || abort("Failed to push solid_log")

    puts "\n=== All gems pushed successfully! ==="
  end

  desc "Tag the current version and push to GitHub"
  task :tag do
    require_relative "solid_log-core/lib/solid_log/core/version"
    version = SolidLog::Core::VERSION
    tag_name = "v#{version}"

    puts "\n=== Creating and pushing git tag #{tag_name} ==="

    # Check if tag already exists
    if system("git rev-parse #{tag_name} > /dev/null 2>&1")
      abort("Tag #{tag_name} already exists!")
    end

    # Create tag
    system("git tag -a #{tag_name} -m 'Release #{tag_name}'") || abort("Failed to create tag")

    # Push tag
    system("git push origin #{tag_name}") || abort("Failed to push tag")

    puts "\n=== Tag #{tag_name} created and pushed! ==="
  end

  desc "Clean up built gem files"
  task :clean do
    puts "\n=== Cleaning up gem files ==="
    system("rm -f solid_log-core/*.gem")
    system("rm -f solid_log-service/*.gem")
    system("rm -f solid_log/*.gem")
    puts "=== Gem files cleaned ==="
  end

  desc "Release all gems: run tests, build, push to RubyGems, and tag"
  task :all do
    require_relative "solid_log-core/lib/solid_log/core/version"
    version = SolidLog::Core::VERSION

    puts "\n" + "=" * 60
    puts "RELEASING SOLIDLOG v#{version}"
    puts "=" * 60

    # 1. Run tests
    puts "\nStep 1/5: Running tests..."
    Rake::Task["test"].invoke

    # 2. Clean up old gem files
    puts "\nStep 2/5: Cleaning up old gem files..."
    Rake::Task["release:clean"].invoke

    # 3. Build gems
    puts "\nStep 3/5: Building gems..."
    Rake::Task["release:build"].invoke

    # 4. Push to RubyGems
    puts "\nStep 4/5: Pushing to RubyGems..."
    Rake::Task["release:push"].invoke

    # 5. Create and push git tag
    puts "\nStep 5/5: Creating and pushing git tag..."
    Rake::Task["release:tag"].invoke

    # Clean up gem files after successful release
    puts "\nCleaning up gem files..."
    Rake::Task["release:clean"].reenable
    Rake::Task["release:clean"].invoke

    puts "\n" + "=" * 60
    puts "SUCCESS! Released SolidLog v#{version}"
    puts "=" * 60
    puts "\nNext steps:"
    puts "- Verify gems at https://rubygems.org/gems/solid_log-core"
    puts "- Check GitHub release at https://github.com/namolnad/solid_log/releases/tag/v#{version}"
    puts "- Update CHANGELOG.md if needed"
  end
end

# Convenience alias
desc "Release all gems (alias for release:all)"
task release: "release:all"

task default: :test
