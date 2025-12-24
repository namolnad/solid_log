namespace :db do
  namespace :log do
    desc "Setup the log database using the SolidLog install generator (tests the real install flow)"
    task setup: :environment do
      puts "Setting up SolidLog database using install generator..."

      # Drop existing database
      Rake::Task["db:drop:log"].invoke rescue nil

      # Run the install generator (this copies schema and generates triggers)
      puts "Running install generator..."
      Rails::Generators.invoke("solid_log:install", ["--force"])

      # Use db:setup:log to create, load schema, and run migrations (just like end users will)
      puts "Running db:setup:log..."
      Rake::Task["db:setup:log"].invoke

      puts "✅ SolidLog database setup complete!"
    end
  end
end
