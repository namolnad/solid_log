namespace :db do
  namespace :log do
    desc "Setup the log database using the SolidLog install generator (tests the real install flow)"
    task setup: :environment do
      puts "Setting up SolidLog database using install generator..."

      # Drop existing database
      Rake::Task["db:drop:log"].invoke rescue nil

      # Run the install generator (this copies schema and generates triggers)
      puts "Running install generator..."
      Rails::Generators.invoke("solid_log:install", [ "--force" ])

      # Create database, load schema (just like end users will)
      puts "Setting up database (create, schema load)..."
      Rake::Task["db:create:log"].invoke
      Rake::Task["db:schema:load:log"].invoke

      puts "✅ SolidLog database setup complete!"
    end
  end
end
