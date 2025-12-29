require "rake/testtask"

desc "Run tests for all gems"
task :test do
  puts "\n=== Running solid_log-core tests ==="
  system("cd solid_log-core && bundle exec rake test") || abort("Core tests failed")

  puts "\n=== Running solid_log-service tests ==="
  system("cd solid_log-service && bundle exec rake test") || abort("Service tests failed")

  puts "\n=== Running solid_log-ui tests ==="
  system("cd solid_log-ui && bundle exec rake test") || abort("UI tests failed")

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

  desc "Run solid_log-ui tests"
  task :ui do
    system("cd solid_log-ui && bundle exec rake test") || abort("UI tests failed")
  end
end

task default: :test
